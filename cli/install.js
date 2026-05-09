'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
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
    console.log(`  6. ${repo} に .github/workflows/vibehawk-review.yml 配置 PR を作成`);
    console.log('     （利用者の gh CLI 認証で操作、CLI は GitHub Secrets を一切 touch しない）');
  }
  console.log('');
  console.log('vibehawk 運営側サーバーへの通信: なし（localhost のみで完結）');
  console.log('ローカルファイルへの書き込み: なし（標準出力のみ）');
  console.log('GitHub Secrets への書き込み: なし（Issue #72 / #74 全手動方針、利用者が GitHub Settings UI で手動登録）');
  console.log('');
  if (dryRun) {
    console.log('⚙️ --dry-run モード: 実際の操作は実行しません。');
    console.log('');
  }
}

async function run({
  port = DEFAULT_PORT,
  openBrowser = defaultOpenBrowser,
  argv = process.argv.slice(3),
  readOwner = promptOwner,
  readConsent = promptConsent,
  workflowPlacer = createWorkflowPr,
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

  console.log('vibehawk: GitHub App Manifest Flow を開始します');
  console.log('');
  console.log('⚠️ 命名統制: vibehawk は App 名を vibehawk-for-<owner> 形式で固定しています。');
  console.log('   利用者は App 名を自由にカスタマイズできません（GitHub Apps の名前ユニーク制約と');
  console.log('   ブランド統制を両立させるための設計上の制約）。');
  console.log('');

  printPlan({ owner, appName, port, dryRun, repo });

  if (dryRun) {
    console.log('vibehawk: --dry-run のため実際の操作はスキップしました。');
    return { dryRun: true, owner, appName, repo: repo || null };
  }

  // Issue #28: 同意確認プロンプト（npm AUP 遵守）
  if (!yes) {
    const consent = await readConsent();
    if (!consent) {
      console.log('vibehawk: 同意が得られなかったためキャンセルしました。');
      return { canceled: true, owner, appName, repo: repo || null };
    }
  } else {
    console.log('vibehawk: --yes / -y フラグにより同意確認をスキップしました。');
  }
  console.log('');

  console.log('このコマンドは利用者の GitHub アカウントに App を作成します。');
  console.log('vibehawk 運営側のサーバーには一切通信しません（localhost のみで完結）。');
  console.log('');

  const manifest = buildManifest({ port, name: appName });

  const code = await waitForCallback({ port, manifest, openBrowser });
  console.log('vibehawk: GitHub から認可コードを受信しました。App credentials に変換します...');
  const credentials = await exchangeCode(code);

  printResult(credentials, appName, repo);

  // Issue #58: --repo 指定時、workflow ファイル PR を対象リポジトリに自動作成
  let workflowPr = null;
  if (repo) {
    try {
      workflowPr = await workflowPlacer({ repo, overwrite });
      if (workflowPr.skipped) {
        console.log('');
        console.log(`⚠️ vibehawk: ${repo} に既存の ${WORKFLOW_PATH} を検出したため PR 作成をスキップしました。`);
        console.log('   既存ファイルを上書きするには --overwrite フラグを付けて再実行してください。');
      } else if (workflowPr.url) {
        console.log('');
        console.log(`✅ vibehawk: workflow PR を作成しました: ${workflowPr.url}`);
        console.log('   PR をマージしてから対象リポジトリで PR を作成すると、vibehawk-for-<owner>[bot] 名義でレビューが投稿されます。');
      }
    } catch (e) {
      console.log('');
      console.log(`⚠️ vibehawk: workflow PR 作成に失敗しました: ${e.message}`);
      console.log('   App 作成は完了しているため、利用者が手動で .github/workflows/vibehawk-review.yml を配置してください。');
    }
  }

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

function printResult(credentials, expectedAppName, repo) {
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

  const templatePath = path.join(__dirname, '..', 'templates', '.github', 'workflows', 'vibehawk-review.yml');
  if (!fs.existsSync(templatePath)) {
    throw new Error(`vibehawk: workflow テンプレートが見つかりません: ${templatePath}`);
  }
  const content = fs.readFileSync(templatePath, 'utf8');

  // gh CLI 存在 / 認証確認
  const ghCheck = spawnSync('gh', ['auth', 'status'], { encoding: 'utf8' });
  if (ghCheck.status !== 0) {
    throw new Error('vibehawk: gh CLI が認証されていません。`gh auth login` を実行してから再試行してください。');
  }

  // 既存ファイル検出
  const exists = spawnSync(
    'gh',
    ['api', `repos/${repo}/contents/${WORKFLOW_PATH}`, '--silent'],
    { encoding: 'utf8' }
  );
  if (exists.status === 0 && !overwrite) {
    return { skipped: true, reason: 'existing-file' };
  }

  // default branch 取得
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

  // default branch の最新 SHA 取得
  const refResult = spawnSync(
    'gh',
    ['api', `repos/${repo}/git/refs/heads/${defaultBranch}`, '--jq', '.object.sha'],
    { encoding: 'utf8' }
  );
  if (refResult.status !== 0) {
    throw new Error(`vibehawk: default branch ${defaultBranch} の SHA 取得に失敗しました`);
  }
  const baseSha = (refResult.stdout || '').trim();

  // 新規ブランチ作成（既存があれば上書き不可、別名で再試行）
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

  // 既存ファイルの sha を取得（上書き時）
  let existingFileSha = null;
  if (exists.status === 0 && overwrite) {
    const shaResult = spawnSync(
      'gh',
      ['api', `repos/${repo}/contents/${WORKFLOW_PATH}`, '--jq', '.sha'],
      { encoding: 'utf8' }
    );
    if (shaResult.status === 0) {
      existingFileSha = (shaResult.stdout || '').trim() || null;
    }
  }

  // ファイルを新ブランチに commit
  const contentBase64 = Buffer.from(content, 'utf8').toString('base64');
  const commitMessage = overwrite
    ? `chore: vibehawk PR auto-review workflow を更新（経路 2 App Installation Token 認証版）`
    : `chore: vibehawk PR auto-review workflow を配置（経路 2 App Installation Token 認証版）`;
  const commitArgs = [
    'api',
    `repos/${repo}/contents/${WORKFLOW_PATH}`,
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
    // ブランチ削除でロールバック
    spawnSync('gh', ['api', `repos/${repo}/git/refs/heads/${branchName}`, '--method', 'DELETE'], { encoding: 'utf8' });
    throw new Error(`vibehawk: workflow ファイルの commit に失敗しました: ${commitResult.stderr || ''}`);
  }

  // PR 作成
  const prBody = [
    '## vibehawk PR auto-review workflow を配置',
    '',
    '`npx vibehawk install` により本 PR を自動作成しました。',
    '',
    '### このファイルが行うこと',
    '',
    '`pull_request` イベントで `claude-code-action` を呼び出し、`vibehawk-for-<owner>[bot]` 名義で PR レビューサマリを投稿します。',
    '',
    '### マージ後の必須セットアップ（CLI は secrets を書き込みません、Issue #72 / #74）',
    '',
    '対象リポジトリの `Settings → Secrets and variables → Actions` で以下 3 つを **手動登録** してください:',
    '',
    '- `VIBEHAWK_APP_ID` — `npx vibehawk install` 実行時に CLI が画面表示した App ID',
    '- `VIBEHAWK_PRIVATE_KEY` — GitHub App Settings ページで生成した `.pem` ファイル全文',
    '- `CLAUDE_CODE_OAUTH_TOKEN` — `npx vibehawk setup-token` で取得した Claude OAuth Token',
    '',
    '### 動作確認',
    '',
    '本 PR をマージ → 任意の PR を作成 → `vibehawk-for-<owner>[bot]` 名義でレビューサマリが投稿されることを確認',
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
    spawnSync(
      'gh',
      ['api', `repos/${repo}/git/refs/heads/${branchName}`, '--method', 'DELETE'],
      { encoding: 'utf8' }
    );
    throw new Error(`vibehawk: PR 作成に失敗しました（ブランチ ${branchName} はロールバック削除済み）: ${prResult.stderr || ''}`);
  }
  const prUrl = (prResult.stdout || '').trim();
  return { url: prUrl, branch: branchName, defaultBranch };
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
  DEFAULT_PORT,
  WORKFLOW_BRANCH,
  WORKFLOW_PATH,
};
