'use strict';

const readline = require('readline');
const { spawnSync } = require('child_process');

// CLAUDE_CODE_OAUTH_TOKEN の取得・登録誘導
//
// 設計判断:
// - Anthropic OAuth client_id を vibehawk が保有することは非推奨（Value 4「公式の道を、迂回せず歩く」）
// - 公式 `claude setup-token` フローに委譲し、利用者がトークンを取得した後に貼り付けてもらう
// - 受け取ったトークンを vibehawk CLI が GitHub Secrets に書き込むことはしない（Issue #72 決定）
// - 利用者が GitHub Settings UI で手動登録する。CLI は登録手順の画面誘導のみを行う
// - 任意で OS ネイティブのクリップボードに置く（明示同意の上、stdin 経由）
// - ローカルファイル・vibehawk 運営側サーバーへの送信は一切しない（メモリ上のみで保持）

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

function defaultRlFactory() {
  return readline.createInterface({ input: process.stdin, output: process.stdout });
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
    rl.question('対象リポジトリ（owner/repo 形式、空欄で URL 表示をスキップ）: ', (answer) => {
      rl.close();
      const repo = (answer || '').trim();
      resolve(repo || null);
    });
  });
}

function buildSettingsUrl(repo) {
  if (!repo) return null;
  if (!/^[A-Za-z0-9_.\-]+\/[A-Za-z0-9_.\-]+$/.test(repo)) return null;
  return `https://github.com/${repo}/settings/secrets/actions/new`;
}

async function confirmClipboard({ rlFactory = defaultRlFactory } = {}) {
  const rl = rlFactory();
  return new Promise((resolve) => {
    rl.question(
      'OAuth Token をクリップボードにコピーしますか？（GitHub Settings に貼付しやすくなります）[Y/n]: ',
      (answer) => {
        rl.close();
        const trimmed = (answer || '').trim();
        resolve(trimmed === '' || /^y(es)?$/i.test(trimmed));
      }
    );
  });
}

function detectClipboardCommand() {
  const platform = process.platform;
  if (platform === 'darwin') {
    return { cmd: 'pbcopy', args: [] };
  }
  if (platform === 'win32') {
    return { cmd: 'clip', args: [] };
  }
  // Linux / その他: xclip → xsel → wl-copy の順で探索
  if (spawnSync('which', ['xclip']).status === 0) {
    return { cmd: 'xclip', args: ['-selection', 'clipboard'] };
  }
  if (spawnSync('which', ['xsel']).status === 0) {
    return { cmd: 'xsel', args: ['--clipboard', '--input'] };
  }
  if (spawnSync('which', ['wl-copy']).status === 0) {
    return { cmd: 'wl-copy', args: [] };
  }
  return null;
}

function copyToClipboard(token) {
  const tool = detectClipboardCommand();
  if (!tool) {
    return {
      success: false,
      reason: 'クリップボードツールが見つかりません（macOS は pbcopy, Linux は xclip/xsel/wl-copy, Windows は clip）',
    };
  }
  // CISO 条件: token は stdin 経由のみで渡す（プロセス引数 / 環境変数に出さない）
  const r = spawnSync(tool.cmd, tool.args, { input: token, encoding: 'utf8' });
  if (r.status !== 0) {
    return {
      success: false,
      reason: `${tool.cmd} がエラー終了しました（exit code ${r.status}）`,
    };
  }
  return { success: true };
}

function printRegistrationInstructions(repo, clipboardCopied) {
  const settingsUrl = buildSettingsUrl(repo);
  console.log('');
  console.log('=== 次の手順: GitHub Settings で手動登録 ===');
  console.log('');
  if (settingsUrl) {
    console.log('1. ブラウザで以下を開く:');
    console.log(`   ${settingsUrl}`);
  } else {
    console.log('1. ブラウザで対象リポジトリの Settings → Secrets and variables → Actions → New repository secret を開く');
  }
  console.log('');
  console.log('2. Name フィールドに以下を入力:');
  console.log('   CLAUDE_CODE_OAUTH_TOKEN');
  console.log('');
  if (clipboardCopied) {
    console.log('3. Secret フィールドに Cmd+V / Ctrl+V で貼付');
  } else {
    console.log('3. Secret フィールドにトークンを貼付（再取得が必要な場合は `claude setup-token` を再実行）');
  }
  console.log('');
  console.log('4. 「Add secret」をクリック');
  console.log('');
  console.log('💡 vibehawk CLI は secret を書き込みません（Issue #72 決定）。');
  console.log('   トークンはメモリ上のみに存在し、本プロセス終了と同時に消去されます。');
}

async function setupToken({
  argv = process.argv.slice(3),
  rlFactory = defaultRlFactory,
  clipboard = copyToClipboard,
  consent = confirmClipboard,
  // Issue #91: ヘッドレス再利用オプション（setup ウィザードから呼ぶ際に有効化）
  // 登録手順印字をウィザード側に任せ、token とクリップボードコピー結果を return で受け取る
  skipPrintInstructions = false,
} = {}) {
  let repo = parseRepoArg(argv);
  if (!repo) {
    repo = await promptRepo({ rlFactory });
  }
  const token = await promptToken({ rlFactory });

  const wantClipboard = await consent({ rlFactory });
  let clipboardResult = { success: false, skipped: !wantClipboard };
  if (wantClipboard) {
    clipboardResult = clipboard(token);
    if (clipboardResult.success) {
      if (!skipPrintInstructions) {
        console.log('✅ クリップボードにコピーしました。');
      }
    } else {
      if (!skipPrintInstructions) {
        console.log(`⚠️ クリップボードコピーに失敗: ${clipboardResult.reason}`);
        console.log('   GitHub Settings にトークンを直接貼付してください。');
      }
    }
  }

  if (!skipPrintInstructions) {
    printRegistrationInstructions(repo, clipboardResult.success === true);
  }

  return {
    repo: repo || null,
    settingsUrl: buildSettingsUrl(repo),
    clipboardCopied: clipboardResult.success === true,
    // Issue #91: ヘッドレス呼び出し時のみ token を return（setup.js が isSensitive: true で扱う）
    // 通常 CLI 経路では token を export せず本関数のスコープで破棄する
    token: skipPrintInstructions ? token : undefined,
  };
}

module.exports = {
  validateToken,
  parseRepoArg,
  promptToken,
  promptRepo,
  buildSettingsUrl,
  confirmClipboard,
  copyToClipboard,
  detectClipboardCommand,
  printRegistrationInstructions,
  setupToken,
  TOKEN_PATTERN,
};
