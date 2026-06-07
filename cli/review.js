'use strict';

// npx vibehawk review: push 前の git diff を CI と同一基準でレビューする read-only CLI（Issue #331）
//
// 設計判断:
// - 実行経路は利用者ローカルの `claude -p`（Claude Code headless、CLAUDE_CODE_OAUTH_TOKEN=Pro/Max 枠）。
//   ANTHROPIC_API_KEY 設定時は fail-fast（-p 非対話が従量課金に化けるのを防ぐ＝追加課金ゼロ保証、Value 4）。
// - read-only（MVV Value 2）: claude には Read/Grep/Glob のみ渡し、Write/Edit/Bash/GitHub 投稿系は渡さない。
//   --fix 等の自動修正フラグは設けない。
// - レビュー基準は子1 #330 の単一ソース templates/review-prompt.md を逐語連結し、CI と観点・severity を揃える。
// - 純関数を export し、run()/preflight() は spawn・env・path を注入可能にしてテストする（cli/oauth.js と同方針）。

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const CRITERIA_PATH = path.join(__dirname, '..', 'templates', 'review-prompt.md');

// severity 序列（fail-on 閾値判定に使う）。数値が大きいほど重大。
const SEVERITY_RANK = { info: 0, trivial: 1, minor: 2, major: 3, critical: 4 };
// text 出力の severity マーカー（CI 基準の絵文字）→ rank
const SEVERITY_EMOJI = { '🔴': 4, '🟠': 3, '🟡': 2, '🔵': 1, '⚪': 0 };

// git ref の許容文字（オプション注入・traversal を二重防御で弾く）
const REF_ALLOWED = /^[A-Za-z0-9._/@{}^~-]+$/;

// intent ラベル 7 種（.claude/rules/intent-labels.md）。--intent はこの集合に限定し、
// 任意テキストがプロンプトに混入するインジェクション経路を塞ぐ（CISO レビュー H-1）。
const INTENT_LABELS = ['feature', 'bugfix', 'performance', 'security', 'refactor', 'infra', 'docs'];

function normalizeIntent(intent) {
  const v = String(intent == null ? '' : intent).trim().replace(/^intent\//, '').toLowerCase();
  if (!INTENT_LABELS.includes(v)) {
    throw new Error(`vibehawk: --intent は ${INTENT_LABELS.join(' / ')} のいずれかです`);
  }
  return v;
}

function validateRef(ref) {
  if (typeof ref !== 'string' || ref.length === 0) {
    throw new Error('vibehawk: --base の ref が空です');
  }
  if (ref.length > 255) {
    throw new Error('vibehawk: --base の ref が長すぎます（255 文字以内）');
  }
  if (ref[0] === '-') {
    throw new Error('vibehawk: --base の ref は - で始められません');
  }
  if (ref.includes('..')) {
    throw new Error('vibehawk: --base の ref に .. は使えません');
  }
  if (!REF_ALLOWED.test(ref)) {
    throw new Error('vibehawk: --base の ref に使用できない文字が含まれます');
  }
  return true;
}

function parseArgs(argv) {
  const opts = { staged: false, base: null, intent: null, output: 'text', failOn: null };
  const list = Array.isArray(argv) ? argv : [];
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    if (a === '--staged') {
      opts.staged = true;
    } else if (a === '--base') {
      opts.base = list[++i];
      if (opts.base == null) throw new Error('vibehawk: --base には ref が必要です');
      validateRef(opts.base);
    } else if (a === '--intent') {
      const v = list[++i];
      if (v == null) throw new Error('vibehawk: --intent にはラベルが必要です');
      opts.intent = normalizeIntent(v);
    } else if (a === '--output') {
      const v = list[++i];
      if (v !== 'text' && v !== 'json') throw new Error("vibehawk: --output は text か json です");
      opts.output = v;
    } else if (a === '--fail-on') {
      const v = (list[++i] || '').toLowerCase();
      if (!(v in SEVERITY_RANK)) {
        throw new Error('vibehawk: --fail-on は critical/major/minor/trivial/info です');
      }
      opts.failOn = v;
    } else {
      throw new Error(`vibehawk: 未知のオプション '${a}'`);
    }
  }
  if (opts.staged && opts.base) {
    throw new Error('vibehawk: --staged と --base は併用できません');
  }
  return opts;
}

function buildDiffArgs(opts) {
  if (opts.staged) return ['diff', '--staged'];
  if (opts.base) return ['diff', `${opts.base}...HEAD`];
  return ['diff', 'HEAD'];
}

// 設定値（外部由来）をプロンプトに埋める前に改行・制御文字を除去する（プロンプトインジェクション防止）
function sanitizeForPrompt(str) {
  if (typeof str !== 'string') return '';
  // eslint-disable-next-line no-control-regex
  return str.replace(/[\u0000-\u001F\u007F]/g, " ").trim();
}

function stripQuotes(s) {
  return s.replace(/^["']/, '').replace(/["']$/, '');
}

// YAML 行末コメントを除去する。`#` がコメントになるのは「行頭 or 空白の後」かつ
// 「クォートの外」のときだけ（RFC 準拠）。クォート内の `#`（path_filters の
// `"foo bar#baz/**"` 等）やパス内の `#`（`val#ue`）は値として保持する。best-effort。
function stripYamlComment(raw) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    if (c === "'" && !inDouble) inSingle = !inSingle;
    else if (c === '"' && !inSingle) inDouble = !inDouble;
    else if (c === '#' && !inSingle && !inDouble && (i === 0 || /\s/.test(raw[i - 1]))) {
      return raw.slice(0, i);
    }
  }
  return raw;
}

// .vibehawk.yaml を best-effort で簡易パースする（node に yaml 依存を増やさない）。
// CI 側（python yaml.safe_load）と完全一致は保証しない。失敗時は空設定を返し、呼出側が既定で継続する。
function readReviewConfig(cwd) {
  const empty = { language: null, pathFilters: [], sizeLimits: {} };
  const file = path.join(cwd, '.vibehawk.yaml');
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (e) {
    return empty;
  }
  try {
    const cfg = { language: null, pathFilters: [], sizeLimits: {} };
    let section = null;
    let sub = null;
    for (const raw of text.split(/\r?\n/)) {
      const line = stripYamlComment(raw);
      if (!line.trim()) continue;
      const indent = line.length - line.trimStart().length;
      const body = line.trim();
      if (indent === 0) {
        section = null;
        sub = null;
        const top = body.match(/^([A-Za-z_]+):\s*(.*)$/);
        if (top) {
          if (top[1] === 'language' && top[2]) cfg.language = stripQuotes(top[2].trim());
          else if (top[1] === 'reviews') section = 'reviews';
        }
        continue;
      }
      if (section !== 'reviews') continue;
      if (indent === 2) {
        sub = null;
        const k = body.match(/^([A-Za-z_]+):\s*(.*)$/);
        if (k && k[1] === 'path_filters') sub = 'path_filters';
        else if (k && k[1] === 'size_limits') sub = 'size_limits';
        continue;
      }
      if (sub === 'path_filters') {
        const li = body.match(/^-\s*(.+)$/);
        if (li) cfg.pathFilters.push(stripQuotes(li[1].trim()));
      } else if (sub === 'size_limits') {
        const kv = body.match(/^([A-Za-z_]+):\s*(\d+)\s*$/);
        if (kv) cfg.sizeLimits[kv[1]] = parseInt(kv[2], 10);
      }
    }
    return cfg;
  } catch (e) {
    return empty;
  }
}

// 変更ファイル数を diff から数える（depth 判定用）
function countFiles(diff) {
  const m = String(diff || '').match(/^diff --git /gm);
  return m ? m.length : 0;
}

// CI 同仕様の段階的劣化（docs/cost-analysis.md）
function pickDepth(fileCount, limits) {
  const full = (limits && limits.full_review_files) || 30;
  const focused = (limits && limits.focused_review_files) || 80;
  const skip = (limits && limits.skip_inline_files) || 3000;
  if (fileCount < full) return 'full';
  if (fileCount < focused) return 'focused';
  if (fileCount < skip) return 'lightweight';
  return 'summary_only';
}

function buildPrompt({ criteria, diff, intent, output, language, pathFilters, depth, fileCount }) {
  const langName = language === 'en' ? 'English' : '日本語';
  const intentLine = intent
    ? `この変更の intent は「${sanitizeForPrompt(intent)}」です。intent の重視軸を優先してレビューしてください。`
    : 'intent ラベルは指定されていません。Critical / Major を主眼に severity-only でレビューしてください。';
  const filters = pathFilters && pathFilters.length
    ? `次の glob に一致するファイルはレビュー対象から除外してください: ${pathFilters.map(sanitizeForPrompt).join(', ')}`
    : '';
  const depthLine = `レビュー粒度（depth）: ${depth}（full=全 severity / focused=Critical・Major 中心 / lightweight=Critical 中心 / summary_only=サマリのみ）。`;
  const outputInstr = output === 'json'
    ? [
        '出力は **JSON オブジェクト 1 個のみ**（前後に説明文・フェンスを付けない）:',
        '{"findings":[{"path":"...","line":N,"severity":"critical|major|minor|trivial|info","category":"...","title":"...","description":"...","suggestion":"...(任意)"}],"summary":{"total":N,"critical":N,"major":N,"minor":N,"trivial":N,"info":N}}',
        'severity は critical / major / minor / trivial / info の小文字いずれかにすること。指摘が無ければ findings は空配列にする。',
      ].join('\n')
    : [
        '出力は severity マーカー（🔴 Critical / 🟠 Major / 🟡 Minor / 🔵 Trivial / ⚪ Info）付きで指摘を列挙すること:',
        '- 各指摘に「ファイル:行番号」と修正提案を含める',
        '- 末尾にサマリ（指摘総数 / severity 別件数）を出力する',
        '指摘が無ければ「指摘なし」と明示する。',
      ].join('\n');
  return [
    '🦅 あなたは vibehawk のローカルレビュアーです。push 前の git diff をレビューします。',
    '',
    '## 制約（厳守）',
    '- read-only: ファイルを変更しない。コードを書かない。自動修正しない。',
    '- GitHub には一切投稿しない（ローカル出力のみ）。',
    `- 出力言語: ${langName}。`,
    intentLine,
    filters,
    depthLine,
    '',
    '## レビュー基準（CI と同一の単一ソース）',
    criteria,
    '',
    '## 出力形式',
    outputInstr,
    '',
    `## レビュー対象 diff（変更ファイル数: ${fileCount}）`,
    '```diff',
    diff,
    '```',
  ].filter((l) => l !== '').join('\n');
}

function parseFindings(stdout, output) {
  if (output !== 'json') return { text: String(stdout || '') };
  const trimmed = String(stdout || '').trim();
  try {
    return JSON.parse(trimmed);
  } catch (e) {
    const m = trimmed.match(/\{[\s\S]*\}/);
    if (m) {
      try {
        return JSON.parse(m[0]);
      } catch (e2) {
        throw new Error('vibehawk: claude の JSON 出力をパースできませんでした');
      }
    }
    throw new Error('vibehawk: claude の JSON 出力をパースできませんでした');
  }
}

// json findings の最大 severity rank（-1 = 指摘なし）
function maxSeverity(findings) {
  let max = -1;
  const arr = (findings && findings.findings) || [];
  for (const f of arr) {
    const s = String((f && f.severity) || '').toLowerCase();
    for (const key of Object.keys(SEVERITY_RANK)) {
      if (s.includes(key) && SEVERITY_RANK[key] > max) max = SEVERITY_RANK[key];
    }
  }
  return max;
}

// text 出力から最大 severity rank を拾う。severity マーカー絵文字のみを根拠にする
// （英単語マッチは "majority"/"informational" 等で誤検出するため不採用、CFO レビュー M-1）。
// text 出力では severity マーカー（🔴🟠🟡🔵⚪）の付与をプロンプトで必須化している。
function maxSeverityFromText(text) {
  let max = -1;
  const s = String(text || '');
  for (const emo of Object.keys(SEVERITY_EMOJI)) {
    if (s.includes(emo) && SEVERITY_EMOJI[emo] > max) max = SEVERITY_EMOJI[emo];
  }
  return max;
}

function shouldFail(maxRank, failOn) {
  if (!failOn) return false;
  const threshold = SEVERITY_RANK[failOn];
  if (threshold == null) return false;
  return maxRank >= threshold;
}

function preflight({ env = process.env, spawn = spawnSync, cwd = process.cwd(), criteriaPath = CRITERIA_PATH } = {}) {
  if (env.ANTHROPIC_API_KEY && String(env.ANTHROPIC_API_KEY).trim()) {
    throw new Error(
      'vibehawk: ANTHROPIC_API_KEY が設定されています。\n'
      + '  追加課金ゼロを守るため、ローカルレビューは Pro/Max 枠の OAuth のみで実行します。\n'
      + "  対処: 'unset ANTHROPIC_API_KEY' で解除するか、'npx vibehawk setup-token' で OAuth を設定してください。"
    );
  }
  const g = spawn('git', ['rev-parse', '--is-inside-work-tree'], { cwd, encoding: 'utf8' });
  if (!g || g.status !== 0 || String(g.stdout || '').trim() !== 'true') {
    throw new Error('vibehawk: git リポジトリ内で実行してください。');
  }
  const c = spawn('claude', ['--version'], { encoding: 'utf8' });
  if (!c || c.error || c.status !== 0) {
    throw new Error(
      'vibehawk: claude コマンドが見つかりません。\n'
      + '  対処: npm install -g @anthropic-ai/claude-code で導入し、npx vibehawk setup-token でログインしてください。'
    );
  }
  if (!fs.existsSync(criteriaPath)) {
    throw new Error(
      'vibehawk: 共通レビュー基準ファイルが見つかりません。\n'
      + '  対処: npx vibehawk@latest review で最新パッケージを取得してください。'
    );
  }
}

function run({
  argv = process.argv.slice(3),
  env = process.env,
  spawn = spawnSync,
  cwd = process.cwd(),
  stdout = process.stdout,
  stderr = process.stderr,
  criteriaPath = CRITERIA_PATH,
} = {}) {
  let opts;
  try {
    opts = parseArgs(argv);
  } catch (e) {
    stderr.write(`${e.message || e}\n`);
    return 1;
  }
  try {
    preflight({ env, spawn, cwd, criteriaPath });
  } catch (e) {
    stderr.write(`${e.message || e}\n`);
    return 1;
  }

  const d = spawn('git', buildDiffArgs(opts), { cwd, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (!d || d.status !== 0) {
    stderr.write(`vibehawk: git diff の取得に失敗しました\n${(d && d.stderr) || ''}\n`);
    return 1;
  }
  const diff = String(d.stdout || '');
  if (!diff.trim()) {
    stderr.write('変更がありません（--staged / --base / 既定 を確認してください）\n');
    return 0;
  }

  const cfg = readReviewConfig(cwd);
  const fileCount = countFiles(diff);
  let depth = pickDepth(fileCount, cfg.sizeLimits);
  if (Buffer.byteLength(diff, 'utf8') > 1.5 * 1024 * 1024) {
    depth = 'summary_only';
    stderr.write('[WARN] diff が大きいため summary_only で実行します\n');
  }

  stderr.write('ℹ️ diff を Anthropic（claude -p）に送信します。機密が含まれる場合は --staged や .vibehawk.yaml の path_filters で絞ってください\n');
  stderr.write('🦅 レビュー中...\n');

  let criteria;
  try {
    criteria = fs.readFileSync(criteriaPath, 'utf8');
  } catch (e) {
    stderr.write('vibehawk: 共通レビュー基準ファイルを読めませんでした。npx vibehawk@latest review を試してください。\n');
    return 1;
  }

  const prompt = buildPrompt({
    criteria,
    diff,
    intent: opts.intent,
    output: opts.output,
    language: cfg.language,
    pathFilters: cfg.pathFilters,
    depth,
    fileCount,
  });

  const r = spawn('claude', ['-p', '--allowed-tools', 'Read,Grep,Glob'], {
    input: prompt,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  if (!r) {
    stderr.write('vibehawk: claude の起動に失敗しました\n');
    return 1;
  }
  if (r.error && r.error.code === 'ENOENT') {
    stderr.write('vibehawk: claude コマンドが見つかりません。npm install -g @anthropic-ai/claude-code で導入してください。\n');
    return 1;
  }
  if (r.status === null) {
    stderr.write(`vibehawk: claude が異常終了しました（シグナル: ${r.signal || '不明'}）\n`);
    return 1;
  }
  if (r.status !== 0) {
    // claude の stderr をそのまま流すと万一の機密混入を広げるため長さを制限する（CISO レビュー M-3）
    const errtext = String(r.stderr || '').slice(0, 2000);
    if (/login|authenticate|authentication|oauth|token|unauthor/i.test(errtext)) {
      stderr.write(`vibehawk: claude の認証が必要です。'npx vibehawk setup-token' で OAuth トークンを設定してください。\n${errtext}\n`);
    } else {
      stderr.write(`vibehawk: claude の実行に失敗しました\n${errtext}\n`);
    }
    return 1;
  }

  const out = String(r.stdout || '');
  if (opts.output === 'json') {
    let parsed;
    try {
      parsed = parseFindings(out, 'json');
    } catch (e) {
      stderr.write(`${e.message || e}\n`);
      return 2;
    }
    stdout.write(`${JSON.stringify(parsed, null, 2)}\n`);
    return shouldFail(maxSeverity(parsed), opts.failOn) ? 1 : 0;
  }
  stdout.write(out.endsWith('\n') ? out : `${out}\n`);
  return shouldFail(maxSeverityFromText(out), opts.failOn) ? 1 : 0;
}

module.exports = {
  CRITERIA_PATH,
  INTENT_LABELS,
  normalizeIntent,
  validateRef,
  parseArgs,
  buildDiffArgs,
  sanitizeForPrompt,
  readReviewConfig,
  countFiles,
  pickDepth,
  buildPrompt,
  parseFindings,
  maxSeverity,
  maxSeverityFromText,
  shouldFail,
  preflight,
  run,
};
