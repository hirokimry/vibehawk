'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const readline = require('readline');
const { spawn, spawnSync } = require('child_process');
const { URL } = require('url');
const { buildManifest } = require('./manifest');
const { buildAppName, parseOwnerArg, validateOwner } = require('./naming');
const { parseRepoArg } = require('./oauth');

const DEFAULT_PORT = 8765;
const TIMEOUT_MS = 5 * 60 * 1000;
const WORKFLOW_BRANCH = 'vibehawk/install-workflow';
const WORKFLOW_PATH = '.github/workflows/vibehawk-review.yml';
// Issue #11: チャット応答 workflow も同時配置
// Issue #350: skip-mark も配置。paths-ignore 該当 PR（lockfile のみ変更等）で required status
//   check `vibehawk` を success post する役割。未配布だと外部リポジトリの lockfile-only PR が
//   `vibehawk` 永久未投稿で BLOCKED になるため、配布対象に含める。
const WORKFLOWS = [
  '.github/workflows/vibehawk-review.yml',
  '.github/workflows/vibehawk-chat.yml',
  '.github/workflows/vibehawk-review-skip-mark.yml',
];

// Issue #346: テンプレート内のランタイム pin プレースホルダ。配布時に commit SHA へ置換する。
const RUNTIME_REF_PLACEHOLDER = '__VIBEHAWK_REF__';

// Issue #347: runtime checkout の解決元 upstream。テンプレートの `repository: hirokimry/vibehawk`
// と一致させる。SHA は必ずこの upstream から解決し、利用者リポジトリ（fork 改ざんタグ）からは
// 解決しない。
const RUNTIME_REPO = 'hirokimry/vibehawk';

// Issue #347: リリースタグ（v<X.Y.Z>）を immutable な commit SHA へ解決する。
//   #346 では runtime checkout の ref を mutable なリリースタグ（git タグは force-update 可能）に
//   していたため、タグ差し替えで既配布の全外部リポジトリ CI へ任意コードが波及する攻撃面が残った。
//   本関数は配布時にタグを commit SHA へ固定し、その攻撃面を構造的に断つ（CISO Major 指摘の根治）。
// 検証は peel 後の最終 commit SHA に対してのみ行う（annotated タグの中間 SHA を commit と誤認しない）。
function resolveRuntimeRefSha(tag, { spawn = spawnSync } = {}) {
  // tag は v<version> 由来（version は package.json）。package.json 改ざん時に YAML 行を分断する
  // 改行・`:` 等が焼き込み先（`# ${tag}`）へ混入する余地を塞ぐ（semver 文字種のみ許可）。
  if (!/^v[0-9A-Za-z.\-+]+$/.test(tag)) {
    throw new Error(`vibehawk: 不正なリリースタグ形式です（${tag}）。配布を中止します。`);
  }

  const fail = (result) => {
    // stderr には GitHub API のエラー詳細（認証状態等）が乗りうるため先頭 200 文字に切り詰めて
    // 過剰な情報露出を避ける（npx 実行者本人のローカル表示のため上限は緩めの 200 文字）。
    const stderr = (result && result.stderr ? String(result.stderr) : '').slice(0, 200);
    throw new Error(
      `vibehawk: リリースタグ ${tag} の commit SHA 解決に失敗しました`
        + '（オフライン / GitHub API 障害 / タグ不在の可能性）。'
        + '不正な ref のまま配布しないため中止します。詳細: '
        + stderr
    );
  };

  const SHA_RE = /^[0-9a-f]{40}$/;
  const parseTypeSha = (result) => {
    // `.object.type + " " + .object.sha` の出力を分解。GitHub API が想定外応答（null / 空 /
    // 形式崩れ）を返した場合は undefined 経路を作らず明示的に throw する（fail-fast の診断品質確保）。
    const parts = String(result.stdout || '').trim().split(' ');
    const objType = parts[0];
    const objSha = parts[1];
    if (!objType || !SHA_RE.test(objSha || '')) {
      throw new Error(
        `vibehawk: リリースタグ ${tag} の解決結果が想定形式ではありません（GitHub API 応答が不正）。配布を中止します。`
      );
    }
    return { objType, objSha };
  };

  const refResult = spawn(
    'gh',
    ['api', `repos/${RUNTIME_REPO}/git/refs/tags/${tag}`, '--jq', '.object.type + " " + .object.sha'],
    { encoding: 'utf8' }
  );
  if (refResult.status !== 0) fail(refResult);
  const { objType: refType, objSha: refSha } = parseTypeSha(refResult);

  let commitSha;
  if (refType === 'commit') {
    // lightweight タグ（gh release create 既定）は commit を直接指す。
    commitSha = refSha;
  } else if (refType === 'tag') {
    // annotated タグはタグオブジェクトを指すため commit へ peel する。
    // nested annotated タグ（タグがタグを指す）でも誤った SHA を pin しないよう、peel 後の
    // オブジェクト型が commit であることを検証し、commit でなければ fail-fast する（根治の担保）。
    const peelResult = spawn(
      'gh',
      ['api', `repos/${RUNTIME_REPO}/git/tags/${refSha}`, '--jq', '.object.type + " " + .object.sha'],
      { encoding: 'utf8' }
    );
    if (peelResult.status !== 0) fail(peelResult);
    const { objType: peelType, objSha: peelSha } = parseTypeSha(peelResult);
    if (peelType !== 'commit') {
      throw new Error(
        `vibehawk: リリースタグ ${tag} が commit を直接指していません（peel 後 type=${peelType}）。`
          + '不正な ref のまま配布しないため中止します。'
      );
    }
    commitSha = peelSha;
  } else {
    throw new Error(
      `vibehawk: リリースタグ ${tag} の参照先オブジェクト型が想定外です（type=${refType}）。配布を中止します。`
    );
  }

  if (!SHA_RE.test(commitSha)) {
    throw new Error(
      `vibehawk: リリースタグ ${tag} から取得した値が commit SHA 形式（40 桁 hex）ではありません（${commitSha}）。配布を中止します。`
    );
  }
  return commitSha;
}

// 配布用 workflow テンプレートを読み込み、ランタイム pin プレースホルダを commit SHA へ置換して返す。
// sha / tag を渡さない直接呼び出し時は内部で resolveRuntimeRefSha を呼ぶ（配布側は解決済み値を渡す）。
function renderWorkflowTemplate(wf, { sha, tag } = {}) {
  const tp = path.join(__dirname, '..', 'templates', wf);
  const content = fs.readFileSync(tp, 'utf8');
  const refTag = tag || `v${require('../package.json').version}`;
  const refSha = sha || resolveRuntimeRefSha(refTag);
  // 可読性のため対応タグ名を YAML 行末コメントで併記する（ref: <sha>  # v<X.Y.Z>）。
  return content.split(RUNTIME_REF_PLACEHOLDER).join(`${refSha}  # ${refTag}`);
}

function parseDryRun(argv) {
  return Array.isArray(argv) && argv.some((a) => a === '--dry-run');
}

function parseYes(argv) {
  return Array.isArray(argv) && argv.some((a) => a === '--yes' || a === '-y');
}

function parseOverwrite(argv) {
  return Array.isArray(argv) && argv.some((a) => a === '--overwrite');
}

function promptConsent({ rlFactory = () => readline.createInterface({ input: process.stdin, output: process.stdout }) } = {}) {
  const rl = rlFactory();
  return new Promise((resolve) => {
    rl.question('上記内容で実行してよろしいですか？ [Y/n]: ', (answer) => {
      rl.close();
      const trimmed = (answer || '').trim();
      // 空入力 / Y / y / Yes / yes は同意とみなす（[Y/n] の Y がデフォルト）
      resolve(trimmed === '' || /^y(es)?$/i.test(trimmed));
    });
  });
}

function printPlan({ owner, appName, port, dryRun, repo }) {
  console.log('=== 実行予定プレビュー ===');
  console.log(`オーナー名:        ${owner}`);
  console.log(`作成される App 名: ${appName}[bot]`);
  console.log(`localhost ポート:  ${port}`);
  if (repo) {
    console.log(`workflow PR 作成先: ${repo}`);
  }
  console.log('');
  console.log('実行される操作:');
  console.log(`  1. localhost:${port} に HTTP サーバーを起動`);
  console.log('  2. ブラウザで GitHub App Manifest Flow を自動オープン');
  console.log('  3. GitHub UI で利用者が「Create」ボタンを押下');
  console.log(`  4. localhost:${port}/callback で App 作成完了を検知`);
  console.log('  5. GitHub API で App credentials を取得（Private Key は画面に印字せず破棄）');
  if (repo) {
    console.log(`  6. ${repo} に以下 2 つの workflow ファイル配置 PR を作成:`);
    for (const wf of WORKFLOWS) {
      console.log(`     - ${wf}`);
    }
    console.log('     （利用者の gh CLI 認証で操作、CLI は GitHub Secrets を一切 touch しない）');
  }
  console.log('');
  console.log('vibehawk 運営側サーバーへの通信: なし（localhost のみで完結）');
  console.log('ローカルファイルへの書き込み: なし（標準出力のみ）');
  console.log('GitHub Secrets への書き込み: なし（Issue #72 / #74 全手動方針、利用者が GitHub Settings UI で手動登録）');
  console.log('');
  // Issue #61: Anthropic への送信通知（GDPR / 個人情報保護法対応、CLI 自体は Anthropic に通信しないが
  //            配置される workflow が claude-code-action 経由で送信する事実を事前告知する）
  console.log('ℹ️ Anthropic への送信について:');
  console.log('   本 CLI 自体は Anthropic に通信しません。ただし配置される workflow');
  console.log('   (.github/workflows/vibehawk-review.yml) は実行時に PR diff・コメントを');
  console.log('   claude-code-action 経由で Anthropic API に送信します。');
  console.log('   送信先・送信内容・利用契約は利用者の Anthropic 契約（Claude Pro / Max OAuth）');
  console.log('   に基づきます。詳細は docs/POLICY.md「データ取扱い方針」を参照してください。');
  console.log('');
  if (dryRun) {
    console.log('⚙️ --dry-run モード: 実際の操作は実行しません。');
    console.log('');
  }
}

// Issue #91: credentials の機密フィールドを破壊的に [REDACTED] 化する内部 helper
// printResult 呼び出し有無に関わらず、run() が credentials を呼び出し元に返す前に必ず実行する
// （CISO Critical: Private Key / client_secret / webhook_secret を呼び出し元のメモリに残さない）
function redactCredentials(credentials) {
  if (!credentials || typeof credentials !== 'object') return credentials;
  if (credentials.pem) {
    credentials.pem = '[REDACTED — vibehawk CLI does not expose Private Key]';
  }
  if (credentials.client_secret) {
    credentials.client_secret = '[REDACTED]';
  }
  if (credentials.webhook_secret) {
    credentials.webhook_secret = '[REDACTED]';
  }
  return credentials;
}

// Issue #60: GitHub Manifest Flow が返した App 名が想定名と一致するか検証する。
// 想定名と異なる場合（GitHub が同名 App 既存により連番を付与した場合等）は
// docs/POLICY.md L175 「命名は vibehawk-for-<owner> 形式に厳密に従うこと」MUST 違反
// となるため、ここで明示的に throw して非ゼロ終了する（CEO 判断 B、2026-05-09）。
//
// throw 前に redactCredentials を呼び、Private Key を呼び出し元のメモリに残さない
// （CISO Critical 条件）。slug / html_url は redact 対象外だが、念のため redact 前に
// ローカル変数に保持してから redact を呼ぶ防御的実装とする。
function assertCanonicalAppName(credentials, expectedAppName) {
  if (!credentials || typeof credentials !== 'object') return;
  if (!expectedAppName) return;
  if (credentials.name === expectedAppName) return;

  // redact 前に必要情報をローカル変数に保持（slug は現状 redact 対象外だが防御的に）
  const actualName = credentials.name;
  const slug = credentials.slug;
  // 既存 App 削除手順用 URL（slug が取れない場合は一般的な Apps 設定ページを案内）
  const appSettingsUrl = slug
    ? `https://github.com/settings/apps/${slug}`
    : 'https://github.com/settings/apps';

  // CISO Critical: throw 経路でも Private Key を呼び出し元メモリに残さない
  redactCredentials(credentials);

  throw new Error(
    [
      `vibehawk: 命名統制衝突を検出しました — 想定名「${expectedAppName}」に対し、`,
      `GitHub から返された実際の名前は「${actualName}」です。`,
      `同名 App が既に存在するため GitHub が連番（例: ${expectedAppName}-2）を付与した可能性があります。`,
      ``,
      `これは docs/POLICY.md「命名は vibehawk-for-<owner> 形式に厳密に従うこと」MUST 違反のため、`,
      `処理を中断します。連番付き App は即時削除してください。`,
      ``,
      `対処手順:`,
      `  1. 連番付き App を GitHub UI で削除: ${appSettingsUrl}`,
      `  2. 既存「${expectedAppName}」App を確認し、不要であれば削除（https://github.com/settings/apps）`,
      `  3. 再実行: npx vibehawk install --owner ${expectedAppName.replace(/^vibehawk-for-/, '')}`,
      `     または別の owner 名で実行: npx vibehawk install --owner <別の名前>`,
      ``,
      `詳細は README.md「命名統制衝突（連番付与）が検出された場合」を参照してください。`,
    ].join('\n')
  );
}

async function run({
  port = DEFAULT_PORT,
  openBrowser = defaultOpenBrowser,
  argv = process.argv.slice(3),
  readOwner = promptOwner,
  readConsent = promptConsent,
  workflowPlacer = createWorkflowPr,
  // Issue #91: ヘッドレス再利用オプション（setup ウィザードから呼ぶ際に有効化）
  skipConsent = false,
  skipPrintResult = false,
} = {}) {
  let owner = parseOwnerArg(argv);
  if (!owner) {
    owner = await readOwner();
  }
  validateOwner(owner);
  const appName = buildAppName(owner);
  const dryRun = parseDryRun(argv);
  const yes = parseYes(argv);
  const overwrite = parseOverwrite(argv);
  const repo = parseRepoArg(argv);

  if (!skipPrintResult) {
    console.log('vibehawk: GitHub App Manifest Flow を開始します');
    console.log('');
    console.log('⚠️ 命名統制: vibehawk は App 名を vibehawk-for-<owner> 形式で固定しています。');
    console.log('   利用者は App 名を自由にカスタマイズできません（GitHub Apps の名前ユニーク制約と');
    console.log('   ブランド統制を両立させるための設計上の制約）。');
    console.log('');

    printPlan({ owner, appName, port, dryRun, repo });
  }

  if (dryRun) {
    if (!skipPrintResult) {
      console.log('vibehawk: --dry-run のため実際の操作はスキップしました。');
    }
    return { dryRun: true, owner, appName, repo: repo || null };
  }

  // Issue #28: 同意確認プロンプト（npm AUP 遵守）
  // Issue #91: skipConsent: true（setup ウィザードから呼ぶ場合）で内部スキップ可能
  if (!yes && !skipConsent) {
    const consent = await readConsent();
    if (!consent) {
      console.log('vibehawk: 同意が得られなかったためキャンセルしました。');
      return { canceled: true, owner, appName, repo: repo || null };
    }
  } else if (yes && !skipPrintResult) {
    console.log('vibehawk: --yes / -y フラグにより同意確認をスキップしました。');
  }

  if (!skipPrintResult) {
    console.log('');
    console.log('このコマンドは利用者の GitHub アカウントに App を作成します。');
    console.log('vibehawk 運営側のサーバーには一切通信しません（localhost のみで完結）。');
    console.log('');
  }

  const manifest = buildManifest({ port, name: appName });

  const code = await waitForCallback({ port, manifest, openBrowser });
  if (!skipPrintResult) {
    console.log('vibehawk: GitHub から認可コードを受信しました。App credentials に変換します...');
  }
  const credentials = await exchangeCode(code);

  // Issue #60 / CEO 判断 B（2026-05-09）: 連番命名検出時はエラーで中断する
  // skipPrintResult: true（setup ウィザード経路）でも throw されるよう、printResult より前に検証する
  assertCanonicalAppName(credentials, appName);

  if (skipPrintResult) {
    // Issue #91: ヘッドレス呼び出し時は printResult を呼ばないが、
    // REDACT は printResult から分離した内部 helper として必ず実行する（CISO Critical）
    redactCredentials(credentials);
  } else {
    printResult(credentials, appName, repo);
  }

  // Issue #58: --repo 指定時、workflow ファイル PR を対象リポジトリに自動作成
  // Issue #91: ヘッドレス呼び出し時は workflow PR 作成を呼び出し元（setup.js）に委譲するためスキップ
  let workflowPr = null;
  if (repo && !skipPrintResult) {
    try {
      workflowPr = await workflowPlacer({ repo, overwrite });
      if (workflowPr.skipped) {
        console.log('');
        const existing = (workflowPr.existingFiles || []).join(', ');
        console.log(`⚠️ vibehawk: ${repo} に既存の workflow ファイルを検出したため PR 作成をスキップしました: ${existing}`);
        console.log('   既存ファイルを上書きするには --overwrite フラグを付けて再実行してください。');
      } else if (workflowPr.url) {
        console.log('');
        console.log(`✅ vibehawk: workflow PR を作成しました: ${workflowPr.url}`);
        console.log('   配置される workflow:');
        for (const wf of (workflowPr.workflows || WORKFLOWS)) {
          console.log(`     - ${wf}`);
        }
        console.log('   PR をマージしてから対象リポジトリで PR を作成すると、vibehawk-for-<owner>[bot] 名義でレビューが投稿されます。');
      }
    } catch (e) {
      console.log('');
      console.log(`⚠️ vibehawk: workflow PR 作成に失敗しました: ${e.message}`);
      console.log('   App 作成は完了しているため、利用者が手動で .github/workflows/vibehawk-review.yml を配置してください。');
    }
  }

  // Issue #91: 念押しの REDACT（既に printResult / skipPrintResult 経路で実行済みだが、
  // 万一の経路漏れがあった場合のフェイルセーフ）
  redactCredentials(credentials);
  return { ...credentials, workflowPr, repo: repo || null };
}

function promptOwner() {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question('GitHub オーナー名（user 名 または org 名）を入力してください: ', (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

function waitForCallback({ port, manifest, openBrowser }) {
  return new Promise((resolve, reject) => {
    // CSRF 対策: cryptographically secure な state を生成し、/start のフォーム POST に埋め込み、
    // /callback で照合する。loopback bind (127.0.0.1) と合わせて多層防御を実現（Issue #59）
    const expectedState = crypto.randomBytes(32).toString('hex');
    const expectedStateBuf = Buffer.from(expectedState, 'utf8');
    const server = http.createServer((req, res) => {
      const reqUrl = new URL(req.url, `http://localhost:${port}`);
      if (reqUrl.pathname === '/start') {
        // GitHub の Manifest Flow は POST 形式の form 送信が必要
        const manifestJson = JSON.stringify(manifest);
        const escaped = manifestJson
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;')
          .replace(/'/g, '&#39;');
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        // state は [a-f0-9] のみの hex 文字列なので HTML エスケープ不要
        res.end(`<!DOCTYPE html>
<html lang="ja">
<head><meta charset="utf-8"><title>vibehawk install</title></head>
<body>
<h1>vibehawk: GitHub に App 作成画面を開きます...</h1>
<form id="form" method="post" action="https://github.com/settings/apps/new">
  <input type="hidden" name="manifest" value="${escaped}" />
  <input type="hidden" name="state" value="${expectedState}" />
</form>
<script>document.getElementById('form').submit();</script>
</body>
</html>`);
      } else if (reqUrl.pathname === '/callback') {
        // CSRF 対策（Issue #59）: state を timing-safe に照合する。
        // 不一致／欠落は CSRF 試行とみなしてサーバ即時停止 + reject で abort する。
        const receivedState = reqUrl.searchParams.get('state') || '';
        const receivedStateBuf = Buffer.from(receivedState, 'utf8');
        const stateValid =
          receivedStateBuf.length === expectedStateBuf.length &&
          crypto.timingSafeEqual(receivedStateBuf, expectedStateBuf);
        if (!stateValid) {
          res.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end('<h1>vibehawk: state mismatch (CSRF 防止のためリクエストを拒否)</h1>');
          clearTimeout(timeoutId);
          server.close();
          reject(new Error('vibehawk: state mismatch — CSRF 防止のためインストールを中断しました。`npx vibehawk install` を再実行してください。'));
          return;
        }
        const code = reqUrl.searchParams.get('code');
        if (!code) {
          res.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end('<h1>vibehawk: code パラメータが見つかりません</h1>');
          return;
        }
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(`<!DOCTYPE html>
<html lang="ja">
<head><meta charset="utf-8"><title>vibehawk install 完了</title></head>
<body>
<h1>🦅 vibehawk: GitHub App 作成完了</h1>
<p>このタブを閉じてターミナルに戻ってください。</p>
</body>
</html>`);
        clearTimeout(timeoutId);
        server.close(() => resolve(code));
      } else {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('not found');
      }
    });

    server.on('error', (e) => {
      clearTimeout(timeoutId);
      reject(e);
    });

    server.listen(port, '127.0.0.1', () => {
      const startUrl = `http://localhost:${port}/start`;
      console.log(`vibehawk: localhost:${port} でブラウザからの App 作成完了を待機中...`);
      console.log(`ブラウザが自動で開かない場合は手動で開いてください: ${startUrl}`);
      console.log('');
      try {
        openBrowser(startUrl);
      } catch (_) {
        // browser 起動失敗は致命的ではない
      }
    });

    const timeoutId = setTimeout(() => {
      server.close();
      reject(new Error(`vibehawk: ${TIMEOUT_MS / 1000} 秒以内に GitHub App が作成されませんでした`));
    }, TIMEOUT_MS);
  });
}

async function exchangeCode(code) {
  const response = await fetch(`https://api.github.com/app-manifests/${encodeURIComponent(code)}/conversions`, {
    method: 'POST',
    headers: {
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'vibehawk-cli',
    },
  });
  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`vibehawk: GitHub API 呼び出しに失敗しました (${response.status}): ${body}`);
  }
  return await response.json();
}

function printResult(credentials, expectedAppName, repo) {
  console.log('');
  console.log('=== GitHub App 作成完了 ===');
  console.log(`App 名:     ${credentials.name}`);
  console.log(`App ID:     ${credentials.id}`);
  console.log(`Slug:       ${credentials.slug}`);
  console.log(`HTML URL:   ${credentials.html_url}`);
  console.log('');
  // Issue #60 / CEO 判断 B: 命名統制衝突は assertCanonicalAppName() で throw されるため
  // ここに到達する時点で credentials.name === expectedAppName が保証されている（責務分離）
  console.log('=== 次のステップ（経路 2 必須化、全手動 secrets 登録、Issue #61 / #72 / #74 確定）===');
  console.log('');
  console.log(`1. App を対象リポジトリにインストール:`);
  console.log(`   ${credentials.html_url}/installations/new`);
  console.log('');
  console.log('2. App ID を GitHub Settings UI で手動登録（CLI は secret を書き込まない）:');
  if (repo) {
    console.log(`   https://github.com/${repo}/settings/secrets/actions/new`);
    console.log(`   Name: VIBEHAWK_APP_ID`);
    console.log(`   Value: ${credentials.id}`);
  } else {
    console.log('   対象リポジトリの Settings → Secrets and variables → Actions → New repository secret');
    console.log(`   Name: VIBEHAWK_APP_ID`);
    console.log(`   Value: ${credentials.id}`);
  }
  console.log('');
  console.log('3. Private Key を GitHub App Settings ページでダウンロードし、Settings UI で手動登録:');
  console.log(`   ${credentials.html_url}`);
  console.log('   → "Generate a private key" → .pem ファイルダウンロード');
  console.log('   → 上記 Settings URL で Name: VIBEHAWK_PRIVATE_KEY、Value に .pem 全文貼付');
  console.log('');
  console.log('4. CLAUDE_CODE_OAUTH_TOKEN を取得・登録:');
  console.log(`   npx vibehawk setup-token${repo ? ' --repo ' + repo : ''}`);
  console.log('');
  if (repo) {
    console.log('5. workflow ファイルは本コマンド実行で自動的に PR 作成される予定（後続表示参照）');
  } else {
    console.log('5. .github/workflows/vibehawk-review.yml を対象リポジトリに配置');
    console.log('   （--repo フラグを付けて install を再実行すると、配置 PR が自動作成されます）');
  }
  console.log('');
  console.log('=== Private Key について（CISO Critical 条件） ===');
  console.log('App の Private Key は GitHub のレスポンスに含まれていますが、本 CLI は');
  console.log('意図的に画面に印字せずメモリ上の参照を [REDACTED] で上書きします。');
  console.log('利用者は GitHub App Settings ページから手動で Private Key を生成・ダウンロードし、');
  console.log('Settings UI で VIBEHAWK_PRIVATE_KEY として登録してください（経路 2 必須化で必要）。');
  console.log('');
  // Issue #134: branch protection 登録が vibehawk 利用の根幹。install 完了画面で
  // 次のステップとして明示し、利用者の repo の branch protection 設定 URL を直リンクで提示する。
  // 順序強制: 3 secrets 全完了 → 初回 PR で vibehawk check 発火 → branch protection 追加。
  console.log('=== 🎯 vibehawk 利用の根幹: branch protection 登録（最重要） ===');
  console.log('');
  console.log('vibehawk は status check `vibehawk` を post しますが、利用者の repo の branch');
  console.log('protection で required 指定しないと merge gate として機能しません。bot review は');
  console.log('required reviewers に count されないため、status check 経路が merge gate の主軸です。');
  console.log('');
  console.log('順序:');
  console.log('  1. 上記 3 secrets が全て登録済みであることを確認');
  console.log('  2. 対象リポジトリで初回 PR を作成して `vibehawk` check を一度発火させる');
  console.log('     （GitHub の仕様上、未発火の check 名は branch protection の検索候補に出ません）');
  console.log('  3. 下記 URL を開き Branch protection rules で');
  console.log('     `Require status checks to pass before merging` を ON →');
  console.log('     検索ボックスに `vibehawk` を入力して required に追加');
  console.log('');
  if (repo) {
    console.log(`  Branch protection 設定 URL: https://github.com/${repo}/settings/branches`);
  } else {
    console.log('  対象リポジトリの Settings → Branches → Branch protection rules');
  }
  console.log('');
  console.log('この登録を行わない場合、vibehawk は指摘を post するのみで merge を止めません。');
  console.log('詳細とトラブルシューティングは docs/troubleshooting.md を参照してください。');
  console.log('');
  // Issue #91: REDACT 処理は redactCredentials() に切り出し（CISO Critical 条件）
  redactCredentials(credentials);
}

function defaultOpenBrowser(url) {
  let cmd;
  let args;
  if (process.platform === 'darwin') {
    cmd = 'open';
    args = [url];
  } else if (process.platform === 'win32') {
    cmd = 'cmd';
    args = ['/c', 'start', '""', url];
  } else {
    cmd = 'xdg-open';
    args = [url];
  }
  const child = spawn(cmd, args, { detached: true, stdio: 'ignore' });
  child.unref();
}

// Issue #58: workflow ファイルを対象リポジトリに PR で配置する
//
// 実装方式:
// - 利用者の gh CLI 認証で gh api を呼ぶ（vibehawk 運営側サーバーに通信しない）
// - npm 同梱の templates/.github/workflows/vibehawk-review.yml をソースとする
// - 既存ファイル検出 → デフォルト中止、--overwrite で上書き
// - 失敗時のロールバックは branch 削除のみ（CLI が secrets を touch していないため）
async function createWorkflowPr({ repo, overwrite = false } = {}) {
  if (!repo || !/^[A-Za-z0-9_.\-]+\/[A-Za-z0-9_.\-]+$/.test(repo)) {
    throw new Error(`vibehawk: --repo の形式が正しくありません: ${repo}`);
  }

  // テンプレートファイル存在確認（Issue #11: review + chat 両方）
  for (const wf of WORKFLOWS) {
    const tp = path.join(__dirname, '..', 'templates', wf);
    if (!fs.existsSync(tp)) {
      throw new Error(`vibehawk: workflow テンプレートが見つかりません: ${tp}`);
    }
  }

  const ghCheck = spawnSync('gh', ['auth', 'status'], { encoding: 'utf8' });
  if (ghCheck.status !== 0) {
    throw new Error('vibehawk: gh CLI が認証されていません。`gh auth login` を実行してから再試行してください。');
  }

  // Issue #347: runtime checkout の ref を commit SHA へ固定するため、配布前に 1 回だけ解決する。
  // ブランチ作成より前に解決して fail-fast することで、解決失敗時に孤立ブランチを作らない。
  // 全 workflow で同一 SHA を共有し、3 回解決による SHA 不一致（TOCTOU）も防ぐ。
  const runtimeTag = `v${require('../package.json').version}`;
  const runtimeRefSha = resolveRuntimeRefSha(runtimeTag);

  const existingFiles = [];
  for (const wf of WORKFLOWS) {
    const r = spawnSync('gh', ['api', `repos/${repo}/contents/${wf}`, '--silent'], { encoding: 'utf8' });
    if (r.status === 0) existingFiles.push(wf);
  }
  if (existingFiles.length > 0 && !overwrite) {
    return { skipped: true, reason: 'existing-files', existingFiles };
  }

  const defaultBranchResult = spawnSync(
    'gh',
    ['api', `repos/${repo}`, '--jq', '.default_branch'],
    { encoding: 'utf8' }
  );
  if (defaultBranchResult.status !== 0) {
    throw new Error(`vibehawk: 対象リポジトリ ${repo} の default branch 取得に失敗しました。${defaultBranchResult.stderr || ''}`);
  }
  const defaultBranch = (defaultBranchResult.stdout || '').trim();
  if (!defaultBranch) {
    throw new Error(`vibehawk: 対象リポジトリ ${repo} の default branch を取得できませんでした`);
  }

  const refResult = spawnSync(
    'gh',
    ['api', `repos/${repo}/git/refs/heads/${defaultBranch}`, '--jq', '.object.sha'],
    { encoding: 'utf8' }
  );
  if (refResult.status !== 0) {
    throw new Error(`vibehawk: default branch ${defaultBranch} の SHA 取得に失敗しました`);
  }
  const baseSha = (refResult.stdout || '').trim();

  let branchName = WORKFLOW_BRANCH;
  let branchCreated = spawnSync(
    'gh',
    ['api', `repos/${repo}/git/refs`, '--method', 'POST', '-f', `ref=refs/heads/${branchName}`, '-f', `sha=${baseSha}`],
    { encoding: 'utf8' }
  );
  if (branchCreated.status !== 0) {
    // 既に存在する場合はタイムスタンプを付けて再試行
    branchName = `${WORKFLOW_BRANCH}-${Date.now()}`;
    branchCreated = spawnSync(
      'gh',
      ['api', `repos/${repo}/git/refs`, '--method', 'POST', '-f', `ref=refs/heads/${branchName}`, '-f', `sha=${baseSha}`],
      { encoding: 'utf8' }
    );
    if (branchCreated.status !== 0) {
      throw new Error(`vibehawk: PR ブランチ作成に失敗しました: ${branchCreated.stderr || ''}`);
    }
  }

  // ロールバック関数（branch 削除）— commit / PR 作成失敗時に呼ぶ
  const rollbackBranch = () => {
    spawnSync('gh', ['api', `repos/${repo}/git/refs/heads/${branchName}`, '--method', 'DELETE'], { encoding: 'utf8' });
  };

  for (const wf of WORKFLOWS) {
    // Issue #346/#347: プレースホルダを commit SHA へ置換してから配布する（pin 付き runtime checkout）。
    // SHA は上で 1 回だけ解決済み（ブランチ作成前に fail-fast 済み）。
    const content = renderWorkflowTemplate(wf, { sha: runtimeRefSha, tag: runtimeTag });
    const contentBase64 = Buffer.from(content, 'utf8').toString('base64');

    let existingFileSha = null;
    if (existingFiles.includes(wf) && overwrite) {
      const shaResult = spawnSync(
        'gh',
        ['api', `repos/${repo}/contents/${wf}`, '--jq', '.sha'],
        { encoding: 'utf8' }
      );
      if (shaResult.status === 0) {
        existingFileSha = (shaResult.stdout || '').trim() || null;
      }
    }

    const wfBaseName = path.basename(wf);
    const commitMessage = overwrite
      ? `chore: vibehawk ${wfBaseName} を更新（経路 2 App Installation Token 認証版）`
      : `chore: vibehawk ${wfBaseName} を配置（経路 2 App Installation Token 認証版）`;
    const commitArgs = [
      'api',
      `repos/${repo}/contents/${wf}`,
      '--method',
      'PUT',
      '-f',
      `message=${commitMessage}`,
      '-f',
      `content=${contentBase64}`,
      '-f',
      `branch=${branchName}`,
    ];
    if (existingFileSha) {
      commitArgs.push('-f', `sha=${existingFileSha}`);
    }
    const commitResult = spawnSync('gh', commitArgs, { encoding: 'utf8' });
    if (commitResult.status !== 0) {
      rollbackBranch();
      throw new Error(`vibehawk: ${wf} の commit に失敗しました（ブランチ ${branchName} はロールバック削除済み）: ${commitResult.stderr || ''}`);
    }
  }

  const prBody = [
    '## vibehawk workflow を配置（PR auto-review + @mention chat）',
    '',
    '`npx vibehawk install` により本 PR を自動作成しました。',
    '',
    '### 配置されるファイル',
    '',
    '- `.github/workflows/vibehawk-review.yml` — PR auto-review（`pull_request` イベントで起動）',
    '- `.github/workflows/vibehawk-chat.yml` — `@vibehawk` メンションチャット応答（`issue_comment` イベントで起動、Issue #11）',
    '',
    '### このファイルが行うこと',
    '',
    '- **review**: PR が立つと `claude-code-action` を呼び出し、`vibehawk-for-<owner>[bot]` 名義で PR レビューサマリを投稿。severity 5 段階の inline comment / auto_resolve / sticky review state も実装（Issue #8 / #9 / #10）。`.vibehawk.yaml` で path_filters / path_instructions / size_limits / language を制御可能',
    '- **chat**: PR / Issue で `@vibehawk` をメンションすると、スレッド全体を読んで応答（Issue #11）',
    '',
    '### マージ後の必須セットアップ（CLI は secrets を書き込みません、Issue #72 / #74）',
    '',
    '対象リポジトリの `Settings → Secrets and variables → Actions` で以下 3 つを **手動登録** してください:',
    '',
    '- `VIBEHAWK_APP_ID` — `npx vibehawk install` 実行時に CLI が画面表示した App ID',
    '- `VIBEHAWK_PRIVATE_KEY` — GitHub App Settings ページで生成した `.pem` ファイル全文',
    '- `CLAUDE_CODE_OAUTH_TOKEN` — `npx vibehawk setup-token` で取得した Claude OAuth Token',
    '',
    '### オプション設定（`.vibehawk.yaml`）',
    '',
    'リポジトリのルートに `.vibehawk.yaml` を置くと、レビュー観点 / コスト制御 / 日本語 locale を制御できます（CodeRabbit 互換、`.coderabbit.yaml` も読み込み可）:',
    '',
    '```yaml',
    'reviews:',
    '  path_filters:',
    '    - "node_modules/**"',
    '    - "dist/**"',
    '  path_instructions:',
    '    - path: "src/auth/**"',
    '      instructions: "認証フローの観点で見て"',
    '  size_limits:',
    '    full_review_files: 30',
    '    focused_review_files: 80',
    '    skip_inline_files: 3000',
    'language: ja',
    '```',
    '',
    '### 動作確認',
    '',
    '1. 本 PR をマージ',
    '2. 任意の PR を作成 → `vibehawk-for-<owner>[bot]` 名義でレビューサマリが投稿されることを確認',
    '3. PR コメントで `@vibehawk` メンション → 応答が投稿されることを確認',
    '',
    '### 関連',
    '',
    '- README: 利用者導入手順',
    '- `docs/secrets-handling.md`: 配布方式の判断根拠',
    '- `docs/SECURITY.md`: 認証経路の設計',
    '',
    '🤖 Generated with [vibehawk](https://github.com/hirokimry/vibehawk)',
  ].join('\n');

  const prResult = spawnSync(
    'gh',
    [
      'pr',
      'create',
      '--repo',
      repo,
      '--base',
      defaultBranch,
      '--head',
      branchName,
      '--title',
      'chore: vibehawk PR auto-review workflow を配置',
      '--body',
      prBody,
    ],
    { encoding: 'utf8' }
  );
  if (prResult.status !== 0) {
    // ブランチ削除でロールバック（CodeRabbit PR #82 指摘: PR 作成失敗時もブランチを残さない）
    rollbackBranch();
    throw new Error(`vibehawk: PR 作成に失敗しました（ブランチ ${branchName} はロールバック削除済み）: ${prResult.stderr || ''}`);
  }
  const prUrl = (prResult.stdout || '').trim();
  return { url: prUrl, branch: branchName, defaultBranch, workflows: WORKFLOWS };
}

module.exports = {
  run,
  waitForCallback,
  exchangeCode,
  parseDryRun,
  parseYes,
  parseOverwrite,
  promptConsent,
  printPlan,
  createWorkflowPr,
  assertCanonicalAppName,
  renderWorkflowTemplate,
  resolveRuntimeRefSha,
  RUNTIME_REF_PLACEHOLDER,
  RUNTIME_REPO,
  DEFAULT_PORT,
  WORKFLOW_BRANCH,
  WORKFLOW_PATH,
  WORKFLOWS,
};
