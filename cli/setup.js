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
const path = require('path');
const clack = require('@clack/prompts');
const install = require('./install');
const oauth = require('./oauth');
// Issue #110: verifyAppInstallation の import は削除（Step 2 を目視確認経路に切替）。
// cli/verify.js での export は将来 App JWT 経由で検証復活させる際の拡張余地として維持する。
const { verifySecret, verifyWorkflow } = require('./verify');
const { parseOwnerArg, validateOwner, buildAppName } = require('./naming');
const { parseRepoArg } = require('./oauth');

const MAX_RETRY = 5;

// Issue #249 / #325: bot アイコン用に同梱する vibehawk ロゴ画像（PNG / 512×512 / 1MB 未満）の絶対パス。
// GitHub App のロゴは Manifest Flow / REST / GraphQL では設定できず、App 所有者の
// Display information 画面での手動アップロードのみ可能なため、案内文で同梱パスを提示する。
const LOGO_PATH = path.join(__dirname, '..', 'assets', 'vibehawk-logo.png');

// Issue #91 完了条件: dogfooding（vibehawk 自身を teardown → setup）で 5 分以内に完走することを確認
// 5 分（300_000 ms）を客観的判定の閾値として使用する
const DOGFOODING_TARGET_MS = 5 * 60 * 1000;

// Issue #104: clack/prompts の note() は `String.prototype.length` 基準でボックス幅を計算し
// 各行に空白パディングを敷くため、East Asian Wide / Emoji（表示幅 2 列 / `.length` 1 や 2）
// が混じると右端の `│` が文字列ごとにズレる。外部依存（string-width 等）を追加せず、
// 各行の `.length` を表示幅と一致させてから clack に渡すことで、内部パディングの過不足を
// 抑え、右端の枠線を揃える（案 B: 自前で表示幅補正、依存追加なし）。
//
// 補正の鍵となる文字: Word Joiner（U+2060）。表示幅 0 で改行を引き起こさないため、
// `.length` を増やす filler として安全に使える。
const WIDTH_FILLER = '⁠';

function isWideCodePoint(cp) {
  // East Asian Wide / Fullwidth と、表示幅 2 列で確定している絵文字ブロックを列挙する。
  // ambiguous なコードポイント（◇ など）は narrow 扱いとし、本ファイルで使う範囲では
  // 実害がないことを枠線アライメントテストで検証する。
  return (
    (cp >= 0x1100 && cp <= 0x115F) || // Hangul Jamo
    (cp >= 0x2E80 && cp <= 0x303E) || // CJK Radicals / Kangxi / CJK Symbols
    (cp >= 0x3041 && cp <= 0x33FF) || // Hiragana / Katakana / CJK Strokes / Enclosed CJK
    (cp >= 0x3400 && cp <= 0x4DBF) || // CJK Unified Ideographs Extension A
    (cp >= 0x4E00 && cp <= 0x9FFF) || // CJK Unified Ideographs
    (cp >= 0xA000 && cp <= 0xA4CF) || // Yi
    (cp >= 0xAC00 && cp <= 0xD7A3) || // Hangul Syllables
    (cp >= 0xF900 && cp <= 0xFAFF) || // CJK Compatibility Ideographs
    (cp >= 0xFE30 && cp <= 0xFE4F) || // CJK Compatibility Forms
    (cp >= 0xFF00 && cp <= 0xFF60) || // Fullwidth Forms
    (cp >= 0xFFE0 && cp <= 0xFFE6) || // Fullwidth Signs
    (cp >= 0x1F300 && cp <= 0x1F64F) || // Misc Symbols and Pictographs / Emoticons
    (cp >= 0x1F680 && cp <= 0x1F6FF) || // Transport & Map
    (cp >= 0x1F900 && cp <= 0x1F9FF) || // Supplemental Symbols and Pictographs
    (cp >= 0x1FA00 && cp <= 0x1FAFF) || // Symbols and Pictographs Extended-A
    (cp >= 0x20000 && cp <= 0x2FFFD) || // CJK Extension B+
    (cp >= 0x30000 && cp <= 0x3FFFD)
  );
}

function isStandaloneEmojiWide(cp) {
  // Emoji_Presentation=Yes な BMP の代表的コードポイント。VS16 なしで 2 列表示される。
  // setup.js で実際に使う ✅ ❌ ⏭️等の見落としを防ぐため明示列挙する。
  return (
    cp === 0x2705 || // ✅
    cp === 0x274C || // ❌
    cp === 0x274E || // ❎
    cp === 0x2728 || // ✨
    cp === 0x2753 || cp === 0x2754 || cp === 0x2755 || cp === 0x2757 || // ❓❔❕❗
    cp === 0x2795 || cp === 0x2796 || cp === 0x2797 // ➕➖➗
  );
}

function displayWidth(str) {
  // 文字列の表示幅（端末で占有する列数）を算出する。サロゲートペアを 1 文字として扱うため
  // Array.from で code point 単位に分解する。
  const chars = Array.from(String(str == null ? '' : str));
  let width = 0;
  let prevWasWide = false;
  for (const ch of chars) {
    const cp = ch.codePointAt(0);
    // VS16 (U+FE0F): emoji presentation 指定。直前が narrow なら 1 列広げて wide 扱いに
    // 昇格させる（ℹ️ / ⚠️ / ⏭️ 等の互換絵文字対応）。
    if (cp === 0xFE0F) {
      if (!prevWasWide) {
        width += 1;
        prevWasWide = true;
      }
      continue;
    }
    if (cp === 0xFE0E) continue;
    if (cp === 0x200B || cp === 0x200C || cp === 0x200D || cp === 0x2060 || cp === 0xFEFF) continue;
    if (cp >= 0x0300 && cp <= 0x036F) continue;
    // Variation Selectors-1..14（U+FE00..U+FE0E）。VS16 は上で個別処理済み
    if (cp >= 0xFE00 && cp <= 0xFE0E) continue;
    if (cp < 0x20 || (cp >= 0x7F && cp < 0xA0)) {
      prevWasWide = false;
      continue;
    }
    if (isWideCodePoint(cp) || isStandaloneEmojiWide(cp)) {
      width += 2;
      prevWasWide = true;
    } else {
      width += 1;
      prevWasWide = false;
    }
  }
  return width;
}

function normalizeLineForNote(line, targetDisplayWidth) {
  // clack.note() は `.length` 基準でボックス幅 r = max(.length) + 2 を決め、各行を
  // `' '.repeat(r - line.length)` で右側へ padding する。
  // 各行の `.length` が表示幅と一致していれば、padding 数 = 表示幅の不足分と等しくなり、
  // 右端の `│` が表示列で揃う。
  const w = displayWidth(line);
  let padded = line + ' '.repeat(Math.max(0, targetDisplayWidth - w));
  const stuff = targetDisplayWidth - padded.length;
  if (stuff > 0) {
    padded += WIDTH_FILLER.repeat(stuff);
  }
  return padded;
}

function normalizeNoteMessage(message) {
  const lines = String(message == null ? '' : message).split('\n');
  const widths = lines.map(displayWidth);
  const target = widths.reduce((max, w) => (w > max ? w : max), 0);
  return lines.map((line) => normalizeLineForNote(line, target)).join('\n');
}

function normalizeNoteTitle(title) {
  // clack.note() は title 長も枠幅 r に算入する（i = title.length）。表示幅 > `.length`
  // のタイトルを渡すと、`r - i - 1` に基づく dash 個数が表示上不足し、右端 `╮` の位置
  // までもがズレる。タイトル側でも `.length` を表示幅に揃える。
  if (title == null) return title;
  const t = String(title);
  const w = displayWidth(t);
  const stuff = w - t.length;
  if (stuff > 0) {
    return t + WIDTH_FILLER.repeat(stuff);
  }
  return t;
}

function note(message, title) {
  // Issue #104: clack.note() の表示幅崩れを正すため、message / title を表示幅基準で
  // 正規化してから委譲する。テスト時に clack.note がモック差し替えされても、本関数経由
  // 呼び出しのまま挙動を検証できる（mock が受け取る引数は正規化後の文字列）。
  return clack.note(normalizeNoteMessage(message), normalizeNoteTitle(title));
}

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

// Issue #356: 既存 App 再利用フロー。App ID は GitHub App の正の整数 id。
// フラグ経由（parseAppId）と対話入力（promptExistingAppId）の両方が本述語を共有し、
// 検証ロジックの二重実装による緩み（片方だけ正規表現が甘い）を防ぐ（CISO M-1）。
function isValidAppId(str) {
  return typeof str === 'string' && /^[1-9][0-9]*$/.test(str);
}

// Issue #356: `--reuse-app` フラグ検出。owner が既に vibehawk-for-<owner> App を
// 作成済みの場合に Manifest Flow（新規作成）をスキップして既存 App を再利用する。
function parseReuseApp(argv) {
  return Array.isArray(argv) && argv.some((a) => a === '--reuse-app');
}

// Issue #356: `--app-id <n>` / `--app-id=<n>` を取得する。isValidAppId を満たさない値は
// null を返し、run() 側で対話プロンプトにフォールバックさせる（"null" 文字列を state に
// 混入させないため、ここでは検証通過した文字列のみ返す、CISO M-1）。
function parseAppId(argv) {
  if (!Array.isArray(argv)) return null;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--app-id' && i + 1 < argv.length) {
      const v = String(argv[i + 1]).trim();
      return isValidAppId(v) ? v : null;
    }
    if (typeof arg === 'string' && arg.startsWith('--app-id=')) {
      const v = arg.slice('--app-id='.length).trim();
      return isValidAppId(v) ? v : null;
    }
  }
  return null;
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

function buildSteps({ owner, repo, reuseApp = false }) {
  // Issue #356: 第 1 ステップは新規作成（app-create）か既存再利用（app-reuse）かで分岐する。
  // 第 2 ステップ以降（app-logo / app-install / secret-* / workflow）は両モード共通で、
  // どちらも 7 ステップを返す（後続ステップは state を読むだけなので変更不要）。
  const firstStep = reuseApp
    ? {
        id: 'app-reuse',
        label: '既存 GitHub App を再利用',
        // run() が実行パスで state.credentials / state.appIdString を事前充足する。
        // 本 run は事前充足済み state の検証のみを行い、clack プロンプト・Manifest Flow を
        // 一切呼ばない（spinner 内インタラクション禁止の既存パターン維持、architect #3 / CISO L-2）。
        // 未充足は通常到達しないが、フェイルセーフとして { ok: false } を返す。
        run: async (state) => {
          if (!state.appIdString || !state.credentials || !Number.isInteger(state.credentials.id)) {
            return { ok: false, hint: '既存 App の App ID が取得できていません（再利用フローの state 未充足）' };
          }
          return {
            ok: true,
            info: `既存 App を再利用: ${state.credentials.name} / App ID: ${state.appIdString}`,
          };
        },
      }
    : {
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
      };
  return [
    firstStep,
    {
      id: 'app-logo',
      label: 'bot アイコン（ロゴ）を差し替え',
      // Issue #249: GitHub App のロゴは Manifest Flow / REST / GraphQL では設定できず、App 所有者の
      // Display information 画面（settings/apps/<slug>）での手動アップロードのみ可能。同梱ロゴへの
      // ドラッグ&ドロップという手動 1 ステップへ導線を縮める。secret-pem と同じ設定 URL を案内する。
      // 認証・認可・credential 経路には一切触れない（getValue / clipboard / isSensitive 値出力なし）。
      // slug 未設定（app-create 失敗等）の場合は URL に 'undefined' を混入させず App 一覧へフォールバックする。
      // Issue #360: macOS では同梱ロゴを Finder で選択表示し、ドラッグ&ドロップを容易にする。
      // open -R はファイルに書き込まない UI 補助。非 macOS / open 不在 / 失敗時はパス表示に
      // フォールバックし、ウィザードを止めない（best-effort のため常に ok を返す）。
      run: async () => {
        const revealed = revealLogoInFinder(LOGO_PATH);
        return {
          ok: true,
          info: revealed
            ? `ロゴ画像を Finder で表示しました: ${LOGO_PATH}`
            : `ロゴ画像の場所: ${LOGO_PATH}`,
        };
      },
      getUrl: (state) => {
        const slug = state.credentials && state.credentials.slug;
        return slug
          ? `https://github.com/settings/apps/${slug}`
          : 'https://github.com/settings/apps';
      },
      getInstructions: () =>
        [
          'App 設定ページの "Display information" を開き、現在のロゴ（GitHub のデフォルトアイコン）に',
          '同梱の vibehawk ロゴ画像をドラッグ&ドロップしてアップロードしてください。',
          `画像の場所: ${LOGO_PATH}`,
          'ロゴ差し替えは任意です。設定しなくても vibehawk の動作には影響しません。',
        ].join('\n'),
      // GitHub にはアイコン設定状態を確認する API が無いため、app-install と同じ目視確認経路にする。
      verify: () => ({ ok: true, reason: 'manual_confirmation', hint: '' }),
      isSensitive: false,
    },
    {
      id: 'app-install',
      label: 'App を対象リポジトリにインストール',
      getUrl: (state) => `${state.credentials && state.credentials.html_url}/installations/new`,
      // Issue #110: `gh api /user/installations` および `/repos/:owner/:repo/installation` は
      // GitHub App user-to-server token / JWT 専用エンドポイントで、利用者の通常 `gh auth login`
      // トークン（PAT）では 403 になる仕様（Issue #56 dogfooding で発覚）。通常 PAT で App の
      // インストール状態を確認する公式 API は GitHub REST API に存在しないため、自動検証を
      // 行わず利用者の目視確認に委ねる。インストール忘れは Step 3 以降（VIBEHAWK_APP_ID 登録
      // → Private Key 生成）で間接的に露呈する。verifyAppInstallation 関数自体は cli/verify.js
      // に残し export を維持する（将来 App JWT 経由で検証復活させる際の拡張余地）。
      getInstructions: () =>
        [
          '上記 URL を開き「Install」を押して対象リポジトリにインストールしてください。',
          '通常 PAT では App インストール状態を自動検証できない GitHub 仕様のため、利用者の目視確認に委ねます。',
          'インストールせずに Enter を押すと後続 Step 3-6 が失敗します。',
        ].join('\n'),
      verify: () => ({ ok: true, reason: 'manual_confirmation', hint: '' }),
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
      // Issue #112: `html_url`（= `https://github.com/apps/<slug>`）は公開インストール案内ページで
      // 「Generate a private key」ボタンが存在しない。Private key は App 所有者専用の設定ページ
      // `https://github.com/settings/apps/<slug>` でのみ生成できるため、こちらの URL を案内する。
      // PR #148 CodeRabbit Major 対応: getUrl は純粋な URL のみを返し、操作説明は getInstructions に寄せる
      // （URL コピー / ブラウザ自動遷移時に説明文が混入しないようにする）。
      getUrl: (state) =>
        `https://github.com/settings/apps/${state.credentials && state.credentials.slug}`,
      // Issue #359: 鍵生成（App 設定ページ = getUrl）と登録（Secrets ページ）の 2 段動線を案内する。
      // secret-app-id ステップは Secrets 登録 URL を案内しているのに secret-pem には無く、
      // .pem ダウンロード後の貼り付け先が分からない不整合があったため、登録先 URL を追記する。
      getInstructions: () =>
        [
          '① 上記 App 設定ページで "Generate a private key" を押下し .pem ファイルをダウンロードしてください。',
          '② ダウンロードした .pem を以下の Secrets 登録ページで登録してください:',
          `   https://github.com/${repo}/settings/secrets/actions/new`,
          'Name: `VIBEHAWK_PRIVATE_KEY` / Value: ダウンロードした .pem 全文（-----BEGIN ... -----END を含む）',
        ].join('\n'),
      verify: () => verifySecret(repo, 'VIBEHAWK_PRIVATE_KEY'),
      // Private Key 自体は CLI が一切 touch しないため getValue / clipboard なし
    },
    {
      id: 'secret-token',
      label: 'CLAUDE_CODE_OAUTH_TOKEN を取得・登録',
      // Issue #361: run() が oauth.setupToken → readline で stdin 入力（トークン貼り付け・
      // クリップボード同意）を行うため、executeStep でスピナーを使わない。スピナーの再描画が
      // 貼り付けプロンプトを上書きして画面から消すのを防ぐ（app-reuse の設計注記と同趣旨）。
      interactiveRun: true,
      run: async (state) => {
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
      // Issue #361: 取得手順（=== Claude OAuth Token の取得 ===、run 内で表示）と登録手順を
      // 文面で区別し、Secret 名・クリップボードからの貼付を明示する。
      getInstructions: () =>
        [
          '取得したトークンを GitHub Secrets に登録します（取得手順は上の「=== Claude OAuth Token の取得 ===」を参照）。',
          'Name: `CLAUDE_CODE_OAUTH_TOKEN`',
          'Value: 取得したトークン（クリップボードにコピー済みなら Cmd+V / Ctrl+V で貼付）',
        ].join('\n'),
      verify: () => verifySecret(repo, 'CLAUDE_CODE_OAUTH_TOKEN'),
      isSensitive: true, // CISO Critical: クリップボードフォールバック時に値を絶対 stdout に出さない
      getValue: (state) => state.oauthToken,
    },
    {
      id: 'workflow',
      label: 'workflow ファイル PR を作成',
      run: async (state) => {
        // Issue #111 / PR #118 CodeRabbit 指摘: Step 5 (secret-token) が skip された場合、
        // executeStep が state.oauthToken に空文字を sentinel として残す。Step 6 開始時に
        // それを検知し、CLAUDE_CODE_OAUTH_TOKEN が未登録のままでは workflow 実行時に
        // claude-code-action 起動が失敗する旨を利用者に案内する。
        // 未登録でも workflow PR 自体は作成する（Issue #111「Step 6 で『OAuth token が未登録です。
        // 手動登録が必要です』と最終メッセージを出力しつつ workflow PR は作成する」要件）。
        if (state && state.oauthToken === '') {
          note(
            [
              'CLAUDE_CODE_OAUTH_TOKEN が未登録です。手動登録が必要です。',
              `   GitHub Secrets UI: https://github.com/${repo}/settings/secrets/actions`,
              '   未登録のまま workflow を実行すると claude-code-action が起動失敗します。',
            ].join('\n'),
            '⚠️ OAuth token 未登録'
          );
        }
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

// Issue #360: macOS で同梱ロゴ画像を Finder に選択表示する（ドラッグ&ドロップの導線短縮）。
// `open -R` はファイルを選択するだけでファイルに書き込まない UI 補助。darwin 以外は何もしない。
// open 不在・例外時は false を返してパス表示にフォールバックし、ウィザードを止めない。
function revealLogoInFinder(logoPath) {
  if (process.platform !== 'darwin') return false;
  try {
    const r = spawnSync('open', ['-R', logoPath]);
    return r.status === 0;
  } catch (e) {
    return false;
  }
}

function tryClipboardCopy(value, isSensitive) {
  // 既存 oauth.copyToClipboard を流用（stdin 経由、プロセス引数禁止、CISO Critical）
  const result = oauth.copyToClipboard(value);
  return { ...result, isSensitive: !!isSensitive };
}

function showClipboardFallback(value, isSensitive, reason) {
  // CISO Critical: isSensitive: true の値は絶対 stdout に出さない
  if (isSensitive) {
    note(
      [
        'クリップボードへのコピーに失敗しました。',
        'GitHub Settings の入力欄に直接貼り付けてください。',
        'トークンを再取得する場合は別ターミナルで `cd /tmp && \\claude setup-token` を再実行してください（alias 回避・HOME 外実行が必要）。',
        `理由: ${reason || 'unknown'}`,
      ].join('\n'),
      '⚠️ クリップボードコピー失敗'
    );
  } else {
    note(
      `クリップボード未対応のため値を表示します:\n  ${value}\n\nGitHub Settings の入力欄にコピー&ペーストしてください。`,
      '⚠️ クリップボード未対応'
    );
  }
}

async function pressEnter(message) {
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
  note(step.label, `[${state.stepIndex + 1}/${state.totalSteps}]`);

  // Issue #91 dogfooding 計測: 各ステップの所要時間を Date.now() で計測する
  const stepStartTime = Date.now();
  const elapsed = () => Date.now() - stepStartTime;

  if (dryRun) {
    summary.push({ id: step.id, label: step.label, status: 'dry-run', durationMs: elapsed() });
    return;
  }

  // CISO 修正必須 2: 再帰呼び出しを MAX_RETRY 上限の for ループに置換し、無限再帰を防止
  if (step.run) {
    let runOk = false;
    let runResult = null;
    let runEarlyExit = false;
    for (let attempt = 0; attempt < MAX_RETRY; attempt++) {
      // Issue #361: interactiveRun のステップ（secret-token）は run() 内で readline による
      // stdin 入力を行うため、スピナーで包まない。スピナーの再描画が貼り付けプロンプトを
      // 上書きして画面から消すのを防ぐ。非対話の run() は従来どおりスピナーで進捗を出す。
      const useSpinner = !step.interactiveRun;
      const s = useSpinner ? clack.spinner() : null;
      if (s) s.start('実行中...');
      let r;
      try {
        r = await step.run(state);
      } catch (e) {
        // Issue #111: 既存実装は throw e で再送出していたため、Step 5 の OAuth token 取得失敗
        // （oauth.setupToken → promptToken → validateToken の reject）でウィザード全体が
        // 「予期しないエラー: vibehawk: OAuth token が空です」で異常終了し Step 6 に到達できなかった。
        // CancelError のみは再 throw（ユーザー中止を尊重）。それ以外の throw は { ok: false, hint }
        // 化して既存 retry/skip/cancel フローに合流させる。
        // CISO 観点: e.message を hint/stdout に出すが、oauth.js の validateToken は throw メッセージ
        // に token 値を埋め込まない実装（"vibehawk: OAuth token が空です" / "...形式が想定外です..."
        // のみ）。これにより isSensitive: true のステップでも値漏洩は起きない（Phase 3 テストで機械検証）。
        if (e instanceof CancelError) {
          if (s) s.stop(`❌ ${e.message}`);
          throw e;
        }
        // 直後の `if (r.ok)` 分岐で s.stop が再度呼ばれるため、ここでは stop しない
        // （二重表示防止、@clack/prompts spinner の stop は idempotent ではないため）
        r = { ok: false, hint: e.message };
      }
      if (r.ok) {
        if (s) s.stop(`✅ ${r.info || '完了'}`);
        runResult = r;
        runOk = true;
        break;
      }
      if (s) {
        s.stop(`❌ ${r.hint || '失敗'}`);
      } else {
        // interactiveRun 経路はスピナーが無いため、失敗を note で可視化してから retry メニューへ
        note(`❌ ${r.hint || '失敗'}`, '❌ 失敗');
      }
      const action = await chooseRetryAction();
      if (action === 'cancel' || clack.isCancel(action)) {
        throw new CancelError(step.id);
      }
      if (action === 'skip') {
        // Issue #111: hint を summary に保存することで、完走サマリで未登録 secrets の詳細を表示できる
        // Issue #111 / PR #118 CodeRabbit 指摘: secret-token を skip した時点で state.oauthToken に
        // 空文字列の sentinel を残し、後続 workflow ステップ開始前に「OAuth token が未登録」を
        // 案内できるようにする（buildState 初期値 null → skip 確定の空文字を区別する）
        if (step.id === 'secret-token') {
          state.oauthToken = '';
        }
        summary.push({ id: step.id, label: step.label, status: 'skipped', hint: r.hint, durationMs: elapsed() });
        runEarlyExit = true;
        break;
      }
    }
    if (runEarlyExit) return;
    if (!runOk) {
      // Issue #111 / PR #118 CodeRabbit 指摘: 最大リトライ到達時も skip 扱いになるので
      // secret-token の sentinel を残しておく
      if (step.id === 'secret-token') {
        state.oauthToken = '';
      }
      summary.push({ id: step.id, label: step.label, status: 'skipped', hint: 'run フェーズが最大リトライ回数に到達', durationMs: elapsed() });
      return;
    }
    if (runResult && runResult.skipped) {
      summary.push({ id: step.id, label: step.label, status: 'skipped', durationMs: elapsed() });
      return;
    }
  }

  if (typeof step.getValue === 'function') {
    const value = step.getValue(state);
    if (value) {
      const cb = tryClipboardCopy(value, step.isSensitive);
      if (cb.success) {
        note('値をクリップボードにコピーしました（Cmd+V / Ctrl+V で貼付できます）', '📋 clipboard');
      } else {
        showClipboardFallback(value, step.isSensitive, cb.reason);
      }
    }
  }

  if (typeof step.verify === 'function') {
    if (step.getUrl) {
      const url = step.getUrl(state);
      const lines = [`ブラウザで以下を開いて操作してください:`, `  ${url}`];
      if (step.getInstructions) {
        lines.push('', step.getInstructions(state));
      }
      note(lines.join('\n'), '👉 操作手順');
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
        // Issue #111 / PR #118 CodeRabbit 指摘: verify フェーズで skip された secret-token も
        // workflow ステップで「OAuth token 未登録」案内対象にするため、空文字 sentinel を残す
        // （verifySecret 失敗 = Secrets 未登録のため、後続 workflow 実行は失敗する前提）
        if (step.id === 'secret-token') {
          state.oauthToken = '';
        }
        summary.push({ id: step.id, label: step.label, status: 'skipped', hint, durationMs: elapsed() });
        return;
      }
    }
    // Issue #111 / PR #118 CodeRabbit 指摘: verify 最大リトライ到達時の skip でも sentinel を残す
    if (step.id === 'secret-token') {
      state.oauthToken = '';
    }
    summary.push({ id: step.id, label: step.label, status: 'skipped', hint: '最大リトライ回数に到達', durationMs: elapsed() });
    return;
  }

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

// Issue #356: App 作成モード（新規 / 既存再利用）を選ばせる。
// 既存 App 検出 API が無いため明示的選択にする（設計判断、docs/troubleshooting.md 参照）。
async function promptAppMode() {
  return clack.select({
    message: 'GitHub App をどうしますか？',
    options: [
      { value: 'new', label: '🆕 新規作成（この owner で初めて vibehawk を導入する）' },
      {
        value: 'reuse',
        label: '♻️ 既存 App を再利用（2 つ目以降のリポジトリ導入。vibehawk-for-<owner> 作成済み）',
      },
    ],
    initialValue: 'new',
  });
}

// Issue #356: 既存 App の App ID を入力させる。App ID は所有者の App 設定ページで確認できる。
// isValidAppId を共有し（CISO M-1）、案内文で App ID の在処と URL 目視確認を促す（CISO M-2）。
async function promptExistingAppId(owner) {
  const appName = buildAppName(owner);
  return clack.text({
    message: `既存 App「${appName}」の App ID（数値）を入力してください（https://github.com/settings/apps/${appName} の "About" で確認できます。URL が自分の App と一致するか目視確認してください）`,
    placeholder: 'example: 1234567',
    validate: (val) => {
      const t = (val || '').trim();
      if (!t) return 'App ID を入力してください';
      if (!isValidAppId(t)) return 'App ID は正の整数で入力してください';
    },
  });
}

async function run({ argv = process.argv.slice(3) } = {}) {
  const dryRun = parseDryRun(argv);
  const state = buildState();

  const wizardStartTime = Date.now();

  // SIGINT/SIGTERM ハンドラ: メモリ参照を null 化してから終了（CISO Critical）
  const onInterrupt = () => {
    clearState(state);
    process.exit(130);
  };
  process.on('SIGINT', onInterrupt);
  process.on('SIGTERM', onInterrupt);

  clack.intro('🦅 vibehawk セットアップウィザード');

  if (!dryRun && !checkGhAuth()) {
    note(
      'gh CLI が未認証です。別ターミナルで `gh auth login` を実行してから再実行してください。',
      '❌ 前提条件エラー'
    );
    clack.cancel('セットアップを中止しました');
    process.exit(1);
  }

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

  // Issue #356: App 作成モード（新規 / 既存再利用）の決定。
  // フラグ（--reuse-app / --app-id）優先、未指定かつ非 dry-run なら対話選択。
  // reuseApp / reuseAppId は run() ローカル変数に留め state には書き込まない（clearState 同期不要、CISO L-1）。
  let reuseApp = parseReuseApp(argv);
  let reuseAppId = parseAppId(argv);
  if (reuseAppId) reuseApp = true; // --app-id 指定は reuse を含意
  if (!dryRun) {
    if (!reuseApp) {
      const mode = await promptAppMode();
      if (clack.isCancel(mode)) {
        clack.cancel('セットアップを中止しました');
        clearState(state);
        process.exit(0);
      }
      reuseApp = mode === 'reuse';
    }
    // 再利用かつ App ID 未取得（フラグ無し or フラグ不正で null）なら対話入力する。
    // parseAppId が null を返した値は state に入れず、必ず検証済み文字列を得る（CISO M-1）。
    if (reuseApp && !reuseAppId) {
      reuseAppId = await promptExistingAppId(owner);
      if (clack.isCancel(reuseAppId)) {
        clack.cancel('セットアップを中止しました');
        clearState(state);
        process.exit(0);
      }
      reuseAppId = typeof reuseAppId === 'string' ? reuseAppId.trim() : reuseAppId;
    }
  }

  // 同意 + プレビュー（npm AUP 遵守、CLI が secret を書き込まない宣言）
  const firstStepLine = reuseApp
    ? `  [1/6] 既存 GitHub App を再利用（App ID 入力済み、新規作成しない）`
    : '  [1/6] GitHub App を作成（localhost のみ、運営側サーバー通信なし）';
  note(
    [
      `owner: ${owner}`,
      `repo:  ${repo}`,
      `mode:  ${dryRun ? 'dry-run（実際の操作は行わない）' : reuseApp ? '通常実行（既存 App 再利用）' : '通常実行（新規 App 作成）'}`,
      '',
      'このウィザードは以下を実行します:',
      firstStepLine,
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
    note(
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

  // Issue #356: 再利用フローは実行パスで state を事前充足する（dry-run は早期 return 済みで到達しない）。
  // slug は命名統制で vibehawk-for-<owner> に固定（owner は validateOwner 検証済み）。
  // html_url は公開 App ページ。後続ステップ（app-install / secret-pem 等）が state から URL を組み立てる。
  // Number.isInteger で再ガードし、"null" 等の不正値が state.appIdString に混入しないことを保証する（CISO M-1）。
  if (reuseApp) {
    const appId = Number(reuseAppId);
    if (!isValidAppId(String(reuseAppId)) || !Number.isInteger(appId)) {
      clack.cancel('既存 App の App ID が不正です（正の整数を指定してください）');
      clearState(state);
      process.exit(1);
    }
    const appName = buildAppName(owner);
    state.credentials = {
      id: appId,
      name: appName,
      slug: appName,
      html_url: `https://github.com/apps/${appName}`,
    };
    state.appIdString = String(appId);
  }

  const STEPS = buildSteps({ owner, repo, reuseApp });
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

  const completed = summary.filter((s) => s.status === 'completed');
  const skipped = summary.filter((s) => s.status === 'skipped');
  const lines = [];
  for (const s of summary) {
    const icon = s.status === 'completed' ? '✅' : s.status === 'skipped' ? '⏭️' : '•';
    const durationLabel = typeof s.durationMs === 'number' ? ` (${formatDuration(s.durationMs)})` : '';
    lines.push(`  ${icon} ${s.label}${durationLabel}${s.hint ? ` — ${s.hint}` : ''}`);
  }

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

  // Issue #111: 未登録 secrets 一覧と次のアクション（Secrets UI URL）を表示
  // skipped ステップから secret 名を抽出し、CEO が手動補完する際の URL を提示する
  const SECRET_STEP_TO_NAME = {
    'secret-app-id': 'VIBEHAWK_APP_ID',
    'secret-pem': 'VIBEHAWK_PRIVATE_KEY',
    'secret-token': 'CLAUDE_CODE_OAUTH_TOKEN',
  };
  const unregisteredSecrets = skipped
    .map((s) => SECRET_STEP_TO_NAME[s.id])
    .filter((name) => typeof name === 'string' && name.length > 0);
  const workflowSkipped = skipped.some((s) => s.id === 'workflow');
  const secretsActionLines = [];
  if (unregisteredSecrets.length > 0) {
    secretsActionLines.push(
      '',
      '⚠️ 未登録 secrets:',
      ...unregisteredSecrets.map((name) => `   - ${name}`),
      '',
      '次のアクション（手動補完）:',
      `   GitHub Secrets UI: https://github.com/${repo}/settings/secrets/actions`,
      '   上記 URL で未登録 secret を Name 完全一致で登録してから動作確認してください。',
    );
  }
  if (workflowSkipped) {
    secretsActionLines.push(
      '',
      '⚠️ workflow PR が未作成です。',
      '   `npx vibehawk install --owner <user>` の workflow 配置経路で手動補完してください。',
    );
  }

  note(
    [
      `完了: ${completed.length}/${STEPS.length}, スキップ: ${skipped.length}`,
      '',
      ...lines,
      ...dogfoodingLines,
      ...secretsActionLines,
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

  // Issue #134: 3 secrets が揃った状態のみ branch protection 誘導を表示する。
  // 未登録 secrets がある状態で branch protection に追加すると全 PR が永続 pending で
  // 完全停止する事故が起きるため、順序強制として secrets 完了を gate にする。
  //
  // workflow ステップは「既存検出によるスキップ（冪等再実行で normal）」と「PR 作成失敗の
  // スキップ（abnormal）」が両方とも summary.status='skipped' になるため、ここの gate には
  // 含めない（PR #151 で指摘された誤表示への対策）。workflow が未配置でも `vibehawk` check は
  // 発火できないだけで、branch protection 設定自体の案内はしてよい。
  const branchProtectionGated = unregisteredSecrets.length === 0;
  if (branchProtectionGated) {
    clack.note(
      [
        '🎯 vibehawk 利用の根幹: branch protection に `vibehawk` を required status check として登録',
        '',
        'この登録を行わない場合、vibehawk は指摘を post するのみで merge を止めません',
        '（bot review は required reviewers に count されないため、status check 経路が merge gate の主軸です）。',
        '',
        '手順:',
        '  1. 対象リポジトリで初回 PR を作成して `vibehawk` check を一度発火させる',
        `     （GitHub の仕様上、未発火の check 名は branch protection の検索候補に出ません）`,
        '  2. 下記 URL を開き Branch protection rules で `Require status checks to pass before merging` を ON',
        `     → 検索ボックスに \`vibehawk\` を入力して required に追加`,
        '',
        `   Branch protection 設定: https://github.com/${repo}/settings/branches`,
        '',
        '詳細手順とトラブルシューティングは docs/troubleshooting.md を参照してください。',
      ].join('\n'),
      '🎯 次のステップ（必須）'
    );
  } else {
    clack.note(
      [
        '⚠️ branch protection への `vibehawk` 登録（vibehawk 利用の根幹）は未登録 secrets があるため案内をスキップしました。',
        '',
        '未登録 secrets を上記の手順で補完してから、`npx vibehawk setup` を再実行するか、',
        `Branch protection 設定（https://github.com/${repo}/settings/branches）で手動補完してください。`,
      ].join('\n'),
      '⚠️ 次のステップ（順序）'
    );
  }

  clack.outro(
    skipped.length === 0
      ? 'すべてのステップが完了しました。次は branch protection に `vibehawk` を required 追加してください（最重要、上記参照）。'
      : 'ウィザード終了。未完了項目を補完してから branch protection 設定に進んでください。'
  );

  clearState(state);
  return { owner, repo, summary, durationMs: totalElapsedMs, meetsDogfoodingTarget: meetsTarget };
}

module.exports = {
  run,
  parseDryRun,
  // Issue #356: 既存 App 再利用フロー関連の export（テスト用）
  isValidAppId,
  parseReuseApp,
  parseAppId,
  checkGhAuth,
  buildSteps,
  buildState,
  clearState,
  CancelError,
  // Issue #91 dogfooding 計測関連の export（テスト用）
  formatDuration,
  DOGFOODING_TARGET_MS,
  // Issue #104 East Asian Width 補正関連の export（テスト用）
  displayWidth,
  normalizeNoteMessage,
  normalizeNoteTitle,
  note,
};
