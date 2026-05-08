'use strict';

const http = require('http');
const readline = require('readline');
const { spawn } = require('child_process');
const { URL } = require('url');
const { buildManifest } = require('./manifest');
const { buildAppName, parseOwnerArg, validateOwner } = require('./naming');

const DEFAULT_PORT = 8765;
const TIMEOUT_MS = 5 * 60 * 1000;

async function run({ port = DEFAULT_PORT, openBrowser = defaultOpenBrowser, argv = process.argv.slice(3), readOwner = promptOwner } = {}) {
  let owner = parseOwnerArg(argv);
  if (!owner) {
    owner = await readOwner();
  }
  validateOwner(owner);
  const appName = buildAppName(owner);

  console.log('vibehawk: GitHub App Manifest Flow を開始します');
  console.log('');
  console.log(`作成される App 名: ${appName}[bot]`);
  console.log('');
  console.log('⚠️ 命名統制: vibehawk は App 名を vibehawk-for-<owner> 形式で固定しています。');
  console.log('   利用者は App 名を自由にカスタマイズできません（GitHub Apps の名前ユニーク制約と');
  console.log('   ブランド統制を両立させるための設計上の制約）。');
  console.log('   詳細は docs/design-philosophy.md「命名統制」セクション参照。');
  console.log('');
  console.log('このコマンドは利用者の GitHub アカウントに App を作成します。');
  console.log('vibehawk 運営側のサーバーには一切通信しません（localhost のみで完結）。');
  console.log('');

  const code = await waitForCallback({ port, manifest, openBrowser });
  console.log('vibehawk: GitHub から認可コードを受信しました。App credentials に変換します...');
  const credentials = await exchangeCode(code);

  printResult(credentials, appName);
  return credentials;
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
        res.end(`<!DOCTYPE html>
<html lang="ja">
<head><meta charset="utf-8"><title>vibehawk install</title></head>
<body>
<h1>vibehawk: GitHub に App 作成画面を開きます...</h1>
<form id="form" method="post" action="https://github.com/settings/apps/new">
  <input type="hidden" name="manifest" value="${escaped}" />
</form>
<script>document.getElementById('form').submit();</script>
</body>
</html>`);
      } else if (reqUrl.pathname === '/callback') {
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

function printResult(credentials, expectedAppName) {
  console.log('');
  console.log('=== GitHub App 作成完了 ===');
  console.log(`App 名:     ${credentials.name}`);
  console.log(`App ID:     ${credentials.id}`);
  console.log(`Slug:       ${credentials.slug}`);
  console.log(`HTML URL:   ${credentials.html_url}`);
  console.log('');
  if (expectedAppName && credentials.name !== expectedAppName) {
    console.log('⚠️ 命名統制衝突検出:');
    console.log(`   想定名: ${expectedAppName}`);
    console.log(`   実際:   ${credentials.name}`);
    console.log('   GitHub 側で同名 App が既に存在する場合、自動的に連番が付与される可能性があります。');
    console.log('   既存の vibehawk-for-<owner> App を一度確認してから再実行してください。');
    console.log('');
  }
  console.log('=== 次のステップ ===');
  console.log(`1. ${credentials.html_url}/installations/new からこの App を対象リポジトリにインストール`);
  console.log('2. 対象リポジトリの Settings → Secrets で CLAUDE_CODE_OAUTH_TOKEN を設定');
  console.log('3. .github/workflows/vibehawk-review.yml を配置');
  console.log('');
  console.log('=== Private Key について ===');
  console.log('App の Private Key は GitHub のレスポンスに含まれていますが、本 CLI は');
  console.log('意図的に画面に印字せず破棄します。Issue #22 の修正により workflow 認証は');
  console.log('secrets.GITHUB_TOKEN を使用し Private Key は不要です。Issue #25 で');
  console.log('vibehawk-for-<owner>[bot] 命名を使う場合は GitHub UI から手動で発行してください。');
  console.log('');
  // Private Key の取り扱い: メモリから即時参照を解除（CISO Critical 条件）
  if (credentials.pem) {
    credentials.pem = '[REDACTED — vibehawk CLI does not expose Private Key]';
  }
  if (credentials.client_secret) {
    credentials.client_secret = '[REDACTED]';
  }
  if (credentials.webhook_secret) {
    credentials.webhook_secret = '[REDACTED]';
  }
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

module.exports = { run, waitForCallback, exchangeCode, DEFAULT_PORT };
