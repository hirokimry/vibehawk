'use strict';

// Issue #91: npx vibehawk setup 対話型ウィザード
//
// 設計判断:
// - 既存 install.run() / oauth.setupToken() / createWorkflowPr() を再利用（後方互換）
// - 6 ステップを @clack/prompts の対話で進行
// - 各ステップは「指示 → Enter → 検証 → OK で次 / NG でリトライ・スキップ・中止」
// - secret 値は構造的に stdout に出さない（CISO Critical: isSensitive: true で分岐）
// - CLI は secret を一切 touch しない（gh secret set / 書込系 gh api を呼ばない）

const { spawnSync } = require('child_process');
const clack = require('@clack/prompts');
const install = require('./install');
const oauth = require('./oauth');
const { verifySecret, verifyAppInstallation, verifyWorkflow } = require('./verify');
const { parseOwnerArg, validateOwner } = require('./naming');
const { parseRepoArg } = require('./oauth');

const MAX_RETRY = 5;

// Issue #91 完了条件: dogfooding（vibehawk 自身を teardown → setup）で 5 分以内に完走することを確認
// 5 分（300_000 ms）を客観的判定の閾値として使用する
const DOGFOODING_TARGET_MS = 5 * 60 * 1000;

function formatDuration(ms) {
  if (typeof ms !== 'number' || !Number.isFinite(ms) || ms < 0) return 'n/a';
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) {
    const seconds = ms / 1000;
    const secondsLabel = seconds.toFixed(1);
    // 境界値（59.95s 以上で toFixed(1) が "60.0" に丸まる）は分単位へ繰り上げて表示する
    if (secondsLabel === '60.0') {
      return '1m0s';
    }
    return `${secondsLabel}s`;
  }
  let minutes = Math.floor(ms / 60000);
  let remainSeconds = Math.round((ms - minutes * 60000) / 1000);
  // 境界値で Math.round が 60 になった場合は分に繰り上げ、秒を 0-59 に正規化する
  if (remainSeconds >= 60) {
    minutes += Math.floor(remainSeconds / 60);
    remainSeconds = remainSeconds % 60;
  }
  return `${minutes}m${remainSeconds}s`;
}

function parseDryRun(argv) {
  return Array.isArray(argv) && argv.some((a) => a === '--dry-run');
}

function checkGhAuth() {
  // ウィザード開始前の早期失敗: gh CLI 未認証なら全ステップが 401 で失敗するので先に止める
  const r = spawnSync('gh', ['auth', 'status'], { encoding: 'utf8' });
  return r.status === 0;
}

function buildState() {
  // クロージャ的に保持される機密参照。SIGINT 時に null 化する
  return {
    credentials: null,
    appIdString: null,
    oauthToken: null,
  };
}

function clearState(state) {
  // CISO Critical: 中断時にメモリ参照を null 化
  if (state) {
    state.credentials = null;
    state.appIdString = null;
    state.oauthToken = null;
  }
}

function buildSteps({ owner, repo }) {
  // STEPS 設定オブジェクト配列（拡張性 + isSensitive で構造的分岐）
  return [
    {
      id: 'app-create',
      label: 'GitHub App を作成',
      run: async (state) => {
        const result = await install.run({
          argv: ['--owner', owner, '--yes'],
          skipConsent: true,
          skipPrintResult: true,
        });
        if (!result || !Number.isInteger(result.id)) {
          return { ok: false, hint: 'App 作成結果に id（数値）が含まれていません' };
        }
        state.credentials = result;
        state.appIdString = String(result.id);
        return { ok: true, info: `App 名: ${result.name || `vibehawk-for-${owner}`} / App ID: ${result.id}` };
      },
    },
    {
      id: 'app-install',
      label: 'App を対象リポジトリにインストール',
      getUrl: (state) => `${state.credentials && state.credentials.html_url}/installations/new`,
      verify: (state) => verifyAppInstallation(repo, state.credentials && state.credentials.id),
      isSensitive: false,
      getValue: (state) => state.appIdString,
    },
    {
      id: 'secret-app-id',
      label: 'VIBEHAWK_APP_ID を Secrets に登録',
      getUrl: () => `https://github.com/${repo}/settings/secrets/actions/new`,
      getInstructions: (state) => `Name: \`VIBEHAWK_APP_ID\` / Value: \`${state.appIdString}\``,
      verify: () => verifySecret(repo, 'VIBEHAWK_APP_ID'),
      isSensitive: false,
      getValue: (state) => state.appIdString,
    },
    {
      id: 'secret-pem',
      label: 'VIBEHAWK_PRIVATE_KEY を生成・登録',
      getUrl: (state) =>
        `${state.credentials && state.credentials.html_url} （"Generate a private key" を押下し .pem をダウンロード後、Secrets に登録）`,
      getInstructions: () => 'Name: `VIBEHAWK_PRIVATE_KEY` / Value: ダウンロードした .pem 全文（-----BEGIN ... -----END を含む）',
      verify: () => verifySecret(repo, 'VIBEHAWK_PRIVATE_KEY'),
      // Private Key 自体は CLI が一切 touch しないため getValue / clipboard なし
    },
    {
      id: 'secret-token',
      label: 'CLAUDE_CODE_OAUTH_TOKEN を取得・登録',
      run: async (state) => {
        // oauth.setupToken は内部で `claude setup-token` 実行案内 → token 入力プロンプト → clipboard コピーを行う
        const result = await oauth.setupToken({
          argv: ['--repo', repo],
          skipPrintInstructions: true,
        });
        if (!result || !result.token) {
          return { ok: false, hint: 'OAuth Token の取得に失敗しました' };
        }
        state.oauthToken = result.token;
        return {
          ok: true,
          info: `Settings URL: ${result.settingsUrl} / clipboard: ${result.clipboardCopied ? 'copied' : 'not copied'}`,
        };
      },
      getUrl: () => `https://github.com/${repo}/settings/secrets/actions/new`,
      getInstructions: () => 'Name: `CLAUDE_CODE_OAUTH_TOKEN` / Value: 取得したトークンを貼付',
      verify: () => verifySecret(repo, 'CLAUDE_CODE_OAUTH_TOKEN'),
      isSensitive: true, // CISO Critical: クリップボードフォールバック時に値を絶対 stdout に出さない
      getValue: (state) => state.oauthToken,
    },
    {
      id: 'workflow',
      label: 'workflow ファイル PR を作成',
      run: async () => {
        // 既存 createWorkflowPr を再利用。冪等性: 既存ファイル検出時は overwrite なしならスキップ判定
        try {
          const result = await install.createWorkflowPr({ repo, overwrite: false });
          if (result && result.skipped) {
            return {
              ok: true,
              info: `既存 workflow を検出してスキップ: ${(result.existingFiles || []).join(', ')}（既存 PR があればマージしてから再実行）`,
              skipped: true,
            };
          }
          return { ok: true, info: `PR URL: ${result && result.url}` };
        } catch (e) {
          return { ok: false, hint: `workflow PR 作成失敗: ${e.message}` };
        }
      },
      verify: () => verifyWorkflow(repo, '.github/workflows/vibehawk-review.yml'),
    },
  ];
}

function tryClipboardCopy(value, isSensitive) {
  // 既存 oauth.copyToClipboard を流用（stdin 経由、プロセス引数禁止、CISO Critical）
  const result = oauth.copyToClipboard(value);
  return { ...result, isSensitive: !!isSensitive };
}

function showClipboardFallback(value, isSensitive, reason) {
  // CISO Critical: isSensitive: true の値は絶対 stdout に出さない
  if (isSensitive) {
    clack.note(
      [
        'クリップボードへのコピーに失敗しました。',
        'GitHub Settings の入力欄に直接貼り付けてください。',
        'トークンを再取得する場合は別ターミナルで `claude setup-token` を再実行してください。',
        `理由: ${reason || 'unknown'}`,
      ].join('\n'),
      '⚠️ クリップボードコピー失敗'
    );
  } else {
    clack.note(
      `クリップボード未対応のため値を表示します:\n  ${value}\n\nGitHub Settings の入力欄にコピー&ペーストしてください。`,
      '⚠️ クリップボード未対応'
    );
  }
}

async function pressEnter(message) {
  // 「ブラウザ操作してから Enter で次へ」のシンプルな gate
  return clack.text({
    message: message || '完了したら Enter を押してください',
    placeholder: '（Enter で進む）',
    defaultValue: '',
  });
}

async function chooseRetryAction() {
  const choice = await clack.select({
    message: '次のアクションを選択してください',
    options: [
      { value: 'retry', label: '🔁 再試行（もう一度検証する）' },
      { value: 'skip', label: '⏭️ スキップ（後で手動補完する）' },
      { value: 'cancel', label: '↩️ 中止（ウィザードを終了する）' },
    ],
    initialValue: 'retry',
  });
  return choice;
}

async function executeStep(step, state, summary, dryRun) {
  clack.note(step.label, `[${state.stepIndex + 1}/${state.totalSteps}]`);

  // Issue #91 dogfooding 計測: 各ステップの所要時間を Date.now() で計測する
  const stepStartTime = Date.now();
  const elapsed = () => Date.now() - stepStartTime;

  if (dryRun) {
    summary.push({ id: step.id, label: step.label, status: 'dry-run', durationMs: elapsed() });
    return;
  }

  // run フェーズ（ある場合）
  // CISO 修正必須 2: 再帰呼び出しを MAX_RETRY 上限の for ループに置換し、無限再帰を防止
  if (step.run) {
    let runOk = false;
    let runResult = null;
    let runEarlyExit = false;
    for (let attempt = 0; attempt < MAX_RETRY; attempt++) {
      const s = clack.spinner();
      s.start('実行中...');
      let r;
      try {
        r = await step.run(state);
      } catch (e) {
        s.stop(`❌ ${e.message}`);
        throw e;
      }
      if (r.ok) {
        s.stop(`✅ ${r.info || '完了'}`);
        runResult = r;
        runOk = true;
        break;
      }
      s.stop(`❌ ${r.hint || '失敗'}`);
      const action = await chooseRetryAction();
      if (action === 'cancel' || clack.isCancel(action)) {
        throw new CancelError(step.id);
      }
      if (action === 'skip') {
        summary.push({ id: step.id, label: step.label, status: 'skipped', durationMs: elapsed() });
        runEarlyExit = true;
        break;
      }
      // retry: 次のループで再実行
    }
    if (runEarlyExit) return;
    if (!runOk) {
      summary.push({ id: step.id, label: step.label, status: 'skipped', hint: 'run フェーズが最大リトライ回数に到達', durationMs: elapsed() });
      return;
    }
    if (runResult && runResult.skipped) {
      summary.push({ id: step.id, label: step.label, status: 'skipped', durationMs: elapsed() });
      return;
    }
  }

  // クリップボードコピー（getValue がある場合）
  if (typeof step.getValue === 'function') {
    const value = step.getValue(state);
    if (value) {
      const cb = tryClipboardCopy(value, step.isSensitive);
      if (cb.success) {
        clack.note('値をクリップボードにコピーしました（Cmd+V / Ctrl+V で貼付できます）', '📋 clipboard');
      } else {
        showClipboardFallback(value, step.isSensitive, cb.reason);
      }
    }
  }

  // 検証フェーズ（ある場合）
  if (typeof step.verify === 'function') {
    if (step.getUrl) {
      const url = step.getUrl(state);
      const lines = [`ブラウザで以下を開いて操作してください:`, `  ${url}`];
      if (step.getInstructions) {
        lines.push('', step.getInstructions(state));
      }
      clack.note(lines.join('\n'), '👉 操作手順');
    }
    for (let attempt = 0; attempt < MAX_RETRY; attempt++) {
      const _enter = await pressEnter('完了したら Enter を押してください');
      if (clack.isCancel(_enter)) {
        throw new CancelError(step.id);
      }
      const s = clack.spinner();
      s.start('検証中...');
      let v;
      try {
        // CISO 修正必須 3: step.verify は将来非同期化される可能性があるため await を付与
        // 同期実装でも await は値をそのまま返すため互換
        v = await step.verify(state);
      } catch (e) {
        s.stop(`❌ 検証実行エラー: ${e.message}`);
        v = { ok: false, hint: e.message };
      }
      if (v && v.ok) {
        s.stop(`✅ 検証 OK`);
        summary.push({ id: step.id, label: step.label, status: 'completed', durationMs: elapsed() });
        return;
      }
      // v が null/undefined を返した場合のガード（TypeError 防止）
      const hint = (v && (v.hint || v.reason)) || '検証失敗';
      s.stop(`❌ ${hint}`);
      const action = await chooseRetryAction();
      if (action === 'cancel' || clack.isCancel(action)) {
        throw new CancelError(step.id);
      }
      if (action === 'skip') {
        summary.push({ id: step.id, label: step.label, status: 'skipped', hint, durationMs: elapsed() });
        return;
      }
      // retry: 次のループで再検証
    }
    summary.push({ id: step.id, label: step.label, status: 'skipped', hint: '最大リトライ回数に到達', durationMs: elapsed() });
    return;
  }

  // run のみで verify なしのステップは success 確定
  summary.push({ id: step.id, label: step.label, status: 'completed', durationMs: elapsed() });
}

class CancelError extends Error {
  constructor(stepId) {
    super(`ウィザードを中止しました（ステップ: ${stepId || 'n/a'}）`);
    this.name = 'CancelError';
  }
}

async function promptOwnerInteractive() {
  const v = await clack.text({
    message: 'GitHub オーナー名（user 名 または org 名）',
    placeholder: 'example: alice',
    validate: (val) => {
      if (!val || !val.trim()) return 'owner を入力してください';
      try {
        validateOwner(val.trim());
      } catch (e) {
        return e.message;
      }
    },
  });
  return typeof v === 'string' ? v.trim() : v;
}

async function promptRepoInteractive() {
  const v = await clack.text({
    message: '対象リポジトリ（owner/repo 形式）',
    placeholder: 'example: alice/my-app',
    validate: (val) => {
      if (!val || !val.trim()) return 'repo を入力してください';
      if (!/^[A-Za-z0-9_.\-]+\/[A-Za-z0-9_.\-]+$/.test(val.trim())) {
        return 'owner/repo 形式で入力してください';
      }
    },
  });
  return typeof v === 'string' ? v.trim() : v;
}

async function run({ argv = process.argv.slice(3) } = {}) {
  const dryRun = parseDryRun(argv);
  const state = buildState();

  // Issue #91 dogfooding 計測: 全体所要時間の開始時刻を記録
  const wizardStartTime = Date.now();

  // SIGINT/SIGTERM ハンドラ: メモリ参照を null 化してから終了（CISO Critical）
  const onInterrupt = () => {
    clearState(state);
    process.exit(130);
  };
  process.on('SIGINT', onInterrupt);
  process.on('SIGTERM', onInterrupt);

  clack.intro('🦅 vibehawk セットアップウィザード');

  // 前提検証: gh CLI 認証
  if (!dryRun && !checkGhAuth()) {
    clack.note(
      'gh CLI が未認証です。別ターミナルで `gh auth login` を実行してから再実行してください。',
      '❌ 前提条件エラー'
    );
    clack.cancel('セットアップを中止しました');
    process.exit(1);
  }

  // owner / repo を決定
  let owner = parseOwnerArg(argv);
  if (!owner && !dryRun) {
    owner = await promptOwnerInteractive();
    if (clack.isCancel(owner)) {
      clack.cancel('セットアップを中止しました');
      clearState(state);
      process.exit(0);
    }
  } else if (!owner && dryRun) {
    owner = 'dry-run-owner';
  }
  let repo = parseRepoArg(argv);
  if (!repo && !dryRun) {
    repo = await promptRepoInteractive();
    if (clack.isCancel(repo)) {
      clack.cancel('セットアップを中止しました');
      clearState(state);
      process.exit(0);
    }
  } else if (!repo && dryRun) {
    repo = 'dry-run-owner/dry-run-repo';
  }

  // 同意 + プレビュー（npm AUP 遵守、CLI が secret を書き込まない宣言）
  clack.note(
    [
      `owner: ${owner}`,
      `repo:  ${repo}`,
      `mode:  ${dryRun ? 'dry-run（実際の操作は行わない）' : '通常実行'}`,
      '',
      'このウィザードは以下を実行します:',
      '  [1/6] GitHub App を作成（localhost のみ、運営側サーバー通信なし）',
      '  [2/6] App をリポジトリにインストール（利用者がブラウザで操作）',
      '  [3/6] VIBEHAWK_APP_ID を Secrets に登録（利用者が GitHub Settings で操作）',
      '  [4/6] VIBEHAWK_PRIVATE_KEY を生成・登録（利用者が GitHub Settings で操作）',
      '  [5/6] CLAUDE_CODE_OAUTH_TOKEN を取得・登録（利用者が GitHub Settings で操作）',
      '  [6/6] workflow ファイル PR を対象リポジトリに作成',
      '',
      'CLI は secret を書き込みません（Issue #72 / #74、docs/secrets-handling.md 案 2）。',
      '',
      'ℹ️ Anthropic への送信について:',
      '   本 CLI 自体は Anthropic に通信しません。ただし配置される workflow は',
      '   実行時に PR diff・コメントを claude-code-action 経由で Anthropic API に送信します。',
      '   送信内容・契約は利用者の Claude Pro / Max OAuth に基づきます（docs/POLICY.md 参照）。',
    ].join('\n'),
    '🦅 vibehawk セットアップ計画'
  );

  if (dryRun) {
    const dryRunElapsedMs = Date.now() - wizardStartTime;
    const dryRunMeetsTarget = dryRunElapsedMs <= DOGFOODING_TARGET_MS;
    clack.note(
      [
        `所要時間: ${formatDuration(dryRunElapsedMs)}`,
        `dogfooding 目標: ${formatDuration(DOGFOODING_TARGET_MS)}（Issue #91 完了条件）`,
      ].join('\n'),
      '⏱️ dogfooding 計測'
    );
    clack.outro('⚙️ --dry-run のため実際の操作は行いませんでした。');
    clearState(state);
    return {
      dryRun: true,
      owner,
      repo,
      durationMs: dryRunElapsedMs,
      meetsDogfoodingTarget: dryRunMeetsTarget,
    };
  }

  const STEPS = buildSteps({ owner, repo });
  state.totalSteps = STEPS.length;
  const summary = [];

  try {
    for (let i = 0; i < STEPS.length; i++) {
      state.stepIndex = i;
      await executeStep(STEPS[i], state, summary, dryRun);
    }
  } catch (e) {
    if (e instanceof CancelError) {
      clack.cancel(e.message);
      clearState(state);
      process.exit(130);
    }
    clack.cancel(`予期しないエラー: ${e.message}`);
    clearState(state);
    process.exit(1);
  }

  // 完了サマリ
  const completed = summary.filter((s) => s.status === 'completed');
  const skipped = summary.filter((s) => s.status === 'skipped');
  const lines = [];
  for (const s of summary) {
    const icon = s.status === 'completed' ? '✅' : s.status === 'skipped' ? '⏭️' : '•';
    // Issue #91 dogfooding 計測: 各ステップの所要時間を表示
    const durationLabel = typeof s.durationMs === 'number' ? ` (${formatDuration(s.durationMs)})` : '';
    lines.push(`  ${icon} ${s.label}${durationLabel}${s.hint ? ` — ${s.hint}` : ''}`);
  }

  // Issue #91 dogfooding 計測: 全体所要時間と 5 分閾値判定
  const totalElapsedMs = Date.now() - wizardStartTime;
  const totalDurationLabel = formatDuration(totalElapsedMs);
  const targetDurationLabel = formatDuration(DOGFOODING_TARGET_MS);
  const meetsTarget = totalElapsedMs <= DOGFOODING_TARGET_MS;
  const dogfoodingLines = [
    '',
    `⏱️ 所要時間: ${totalDurationLabel} / 目標 ${targetDurationLabel}（Issue #91 完了条件: dogfooding 5 分以内）`,
    meetsTarget
      ? `🎯 5 分以内達成（${totalDurationLabel}）— Issue #91 の dogfooding 完了条件をクリア`
      : `⚠️ 5 分を超えました（${totalDurationLabel}）— ボトルネック分析: 上記の所要時間ログを確認してください`,
  ];

  clack.note(
    [
      `完了: ${completed.length}/${STEPS.length}, スキップ: ${skipped.length}`,
      '',
      ...lines,
      ...dogfoodingLines,
      ...(skipped.length > 0
        ? [
            '',
            '⚠️ スキップされた項目があります。`npx vibehawk setup --owner <user> --repo <owner>/<repo>` を再実行するか、',
            '   docs/POLICY.md の「個別実行」手順で手動補完してください。',
          ]
        : []),
    ].join('\n'),
    '🎉 セットアップ完了'
  );

  clack.outro(
    skipped.length === 0
      ? 'すべてのステップが完了しました。任意の PR を作成すると vibehawk-for-<owner>[bot] 名義でレビューが投稿されます。'
      : 'ウィザード終了。未完了項目を補完してから動作確認してください。'
  );

  clearState(state);
  return { owner, repo, summary, durationMs: totalElapsedMs, meetsDogfoodingTarget: meetsTarget };
}

module.exports = {
  run,
  parseDryRun,
  checkGhAuth,
  buildSteps,
  buildState,
  clearState,
  CancelError,
  // Issue #91 dogfooding 計測関連の export（テスト用）
  formatDuration,
  DOGFOODING_TARGET_MS,
};
