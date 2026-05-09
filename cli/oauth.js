'use strict';

const readline = require('readline');
const { execFileSync, spawnSync } = require('child_process');

// CLAUDE_CODE_OAUTH_TOKEN の取得・登録（Issue #26）
//
// 設計判断:
// - Anthropic OAuth client_id を vibehawk が保有することは非推奨（Value 4「公式の道を、迂回せず歩く」）
// - 公式 `claude setup-token` フローに委譲し、利用者がトークンを取得した後に貼り付けてもらう
// - vibehawk は受け取ったトークンを `gh secret set` で対象リポジトリに登録する
// - ローカルにトークンを永続化しない（メモリ上のみ）

// CLAUDE_CODE_OAUTH_TOKEN は Claude OAuth から発行される長い文字列
// 公開仕様で形式は完全には公表されていないが、最低限の長さ・文字種を検証する
const TOKEN_PATTERN = /^[A-Za-z0-9_\-.+\/=]{32,}$/;

function validateToken(token) {
  if (typeof token !== 'string' || token.length === 0) {
    throw new Error('vibehawk: OAuth token が空です');
  }
  if (!TOKEN_PATTERN.test(token)) {
    throw new Error(
      'vibehawk: OAuth token の形式が想定外です（最低 32 文字の英数字 / -_.+/= が必要）'
    );
  }
  return true;
}

async function promptToken({ rlFactory = defaultRlFactory } = {}) {
  console.log('=== Claude OAuth Token の取得 ===');
  console.log('別ターミナルで以下のコマンドを実行し、表示されたトークンをコピーしてください:');
  console.log('');
  console.log('  claude setup-token');
  console.log('');
  console.log('（公式: https://claude.com/claude-code 参照。claude CLI 未インストールの場合は');
  console.log(' `npm install -g @anthropic-ai/claude-code` 等で導入してください）');
  console.log('');
  const rl = rlFactory();
  return new Promise((resolve, reject) => {
    rl.question('取得した CLAUDE_CODE_OAUTH_TOKEN を貼り付けてください（Ctrl+C でキャンセル）: ', (answer) => {
      rl.close();
      const token = (answer || '').trim();
      try {
        validateToken(token);
        resolve(token);
      } catch (e) {
        reject(e);
      }
    });
  });
}

function defaultRlFactory() {
  return readline.createInterface({ input: process.stdin, output: process.stdout });
}

function parseRepoArg(argv) {
  if (!Array.isArray(argv)) return null;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--repo' && i + 1 < argv.length) {
      return argv[i + 1].trim();
    }
    if (typeof arg === 'string' && arg.startsWith('--repo=')) {
      return arg.slice('--repo='.length).trim();
    }
  }
  return null;
}

async function promptRepo({ rlFactory = defaultRlFactory } = {}) {
  const rl = rlFactory();
  return new Promise((resolve) => {
    rl.question('対象リポジトリ（owner/repo 形式、空欄でスキップ）: ', (answer) => {
      rl.close();
      const repo = (answer || '').trim();
      resolve(repo || null);
    });
  });
}

function checkSecretExists(repo) {
  if (!repo) return false;
  const r = spawnSync('gh', ['secret', 'list', '--repo', repo, '--json', 'name'], {
    encoding: 'utf8',
  });
  if (r.status !== 0) {
    return false;
  }
  try {
    const list = JSON.parse(r.stdout || '[]');
    return Array.isArray(list) && list.some((s) => s && s.name === 'CLAUDE_CODE_OAUTH_TOKEN');
  } catch (_) {
    return false;
  }
}

async function confirmOverwrite({ rlFactory = defaultRlFactory } = {}) {
  const rl = rlFactory();
  return new Promise((resolve) => {
    rl.question('既存の CLAUDE_CODE_OAUTH_TOKEN を上書きしますか？ [y/N]: ', (answer) => {
      rl.close();
      resolve(/^y(es)?$/i.test((answer || '').trim()));
    });
  });
}

function setSecret(repo, token) {
  if (!repo) {
    throw new Error('vibehawk: --repo が指定されていないため secret 登録をスキップします');
  }
  // input オプション経由で stdin に token を渡し、プロセス引数（ps aux / /proc/<pid>/cmdline）への
  // 露出を避ける。--body フラグは使用しない（CISO Critical 条件: トークン非露出）。
  execFileSync('gh', ['secret', 'set', 'CLAUDE_CODE_OAUTH_TOKEN', '--repo', repo], {
    input: token,
    encoding: 'utf8',
    stdio: ['pipe', 'inherit', 'inherit'],
  });
}

async function setupToken({
  argv = process.argv.slice(3),
  rlFactory = defaultRlFactory,
} = {}) {
  let repo = parseRepoArg(argv);
  if (!repo) {
    repo = await promptRepo({ rlFactory });
  }
  const token = await promptToken({ rlFactory });

  if (!repo) {
    console.log('');
    console.log('⚠️ --repo 指定なしのため secret 登録はスキップしました。');
    console.log('  手動で `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner/repo>` を実行してください。');
    return { token, repo: null, skipped: true };
  }

  if (checkSecretExists(repo)) {
    const ok = await confirmOverwrite({ rlFactory });
    if (!ok) {
      console.log('vibehawk: 既存 secret を保持しました（上書きキャンセル）。');
      return { token, repo, skipped: true };
    }
  }

  setSecret(repo, token);
  console.log(`vibehawk: ${repo} に CLAUDE_CODE_OAUTH_TOKEN を登録しました。`);
  return { token, repo, skipped: false };
}

module.exports = {
  validateToken,
  parseRepoArg,
  promptToken,
  promptRepo,
  checkSecretExists,
  confirmOverwrite,
  setSecret,
  setupToken,
  TOKEN_PATTERN,
};
