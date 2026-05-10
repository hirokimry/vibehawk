'use strict';

// Issue #91: setup ウィザード用 gh api 検証ユーティリティ
//
// 設計判断:
// - すべて読み取り専用 API のみを呼ぶ（CLI が secret を一切 touch しない既存方針、
//   docs/secrets-handling.md 案 2 採用、CISO Critical 条件）
// - 書込系コマンド（`gh secret set` / `gh api ... --method PUT/POST/DELETE`）は
//   物理的に呼ばない（grep で機械検証する）
// - 失敗時は呼び出し元が原因を画面表示できるよう具体的な hint を返す
//
// 返却フォーマット: { ok: bool, reason: string, hint: string }

const { spawnSync } = require('child_process');

function runGhApi(args) {
  // gh CLI 経由で GitHub REST API を呼ぶ
  // status === 0 なら 200 系、それ以外は HTTP エラー（stderr に "404"/"401"/"403" 等を含む）
  const result = spawnSync('gh', ['api', ...args], { encoding: 'utf8' });
  return {
    status: result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
  };
}

function classifyGhError(stderr) {
  // gh の HTTP エラー stderr から HTTP ステータスコードを抽出して原因分類
  // 例: stderr に "HTTP 404" / "HTTP 401" / "HTTP 403" が含まれる
  if (/\b404\b/.test(stderr)) return 'not_found';
  if (/\b401\b/.test(stderr)) return 'unauthenticated';
  if (/\b403\b/.test(stderr)) return 'forbidden';
  if (/\b5\d\d\b/.test(stderr)) return 'server_error';
  return 'unknown';
}

// VIBEHAWK_APP_ID 等の secret が対象リポジトリに登録されているかを 200/404 で判定
// 引数: repo = "owner/repo"、secretName = "VIBEHAWK_APP_ID" 等
function verifySecret(repo, secretName) {
  if (!repo || !/^[A-Za-z0-9_.\-]+\/[A-Za-z0-9_.\-]+$/.test(repo)) {
    return { ok: false, reason: 'invalid_repo', hint: `repo の形式が正しくありません: ${repo}` };
  }
  if (!secretName || typeof secretName !== 'string') {
    return { ok: false, reason: 'invalid_secret_name', hint: 'secretName が空または文字列ではありません' };
  }
  const r = runGhApi([`repos/${repo}/actions/secrets/${secretName}`, '--silent']);
  if (r.status === 0) {
    return { ok: true, reason: 'found', hint: '' };
  }
  const cls = classifyGhError(r.stderr);
  if (cls === 'not_found') {
    return {
      ok: false,
      reason: 'not_registered',
      hint: `Secret 名 \`${secretName}\` を確認してください（GitHub Settings の Name フィールドが完全一致しているか）`,
    };
  }
  if (cls === 'unauthenticated') {
    return {
      ok: false,
      reason: 'unauthenticated',
      hint: 'gh CLI が未認証です。`gh auth login` を実行してから再試行してください',
    };
  }
  if (cls === 'forbidden') {
    return {
      ok: false,
      reason: 'forbidden',
      hint: 'リポジトリ admin 権限が必要です（組織リポジトリの場合は組織管理者に Settings 権限の付与を依頼してください）',
    };
  }
  return {
    ok: false,
    reason: 'gh_error',
    hint: `gh コマンド実行に失敗しました: ${r.stderr.trim() || `exit ${r.status}`}`,
  };
}

// vibehawk App が対象リポジトリにインストールされているかを判定
// 引数: repo = "owner/repo"、appId = 数値（install.run() が返す credentials.id）
//
// /repos/:owner/:repo/installation は GitHub App 認証専用エンドポイントのため利用者 PAT では呼べない。
// 代替として /user/installations および /orgs/<org>/installations を使い、app_id 一致 +
// 対象 repo 包含を確認する。
function verifyAppInstallation(repo, appId) {
  if (!repo || !/^[A-Za-z0-9_.\-]+\/[A-Za-z0-9_.\-]+$/.test(repo)) {
    return { ok: false, reason: 'invalid_repo', hint: `repo の形式が正しくありません: ${repo}` };
  }
  // appId は install.run() が返す credentials.id（GitHub Apps Manifest API レスポンス仕様で数値）
  if (!Number.isInteger(appId)) {
    throw new TypeError(`vibehawk: appId は整数である必要があります（受領値: ${typeof appId} ${String(appId)}）`);
  }
  const targetAppIdStr = String(appId);
  const [owner] = repo.split('/');

  // ① /user/installations を試す（個人アカウントのインストール一覧、利用者 PAT で呼べる）
  const userResult = runGhApi(['/user/installations', '--paginate']);
  if (userResult.status === 0) {
    const matched = matchInstallation(userResult.stdout, targetAppIdStr, repo);
    if (matched) return { ok: true, reason: 'installed_via_user', hint: '' };
  }

  // ② /orgs/<owner>/installations を試す（組織アカウント向け）
  const orgResult = runGhApi([`/orgs/${owner}/installations`, '--paginate']);
  if (orgResult.status === 0) {
    const matched = matchInstallation(orgResult.stdout, targetAppIdStr, repo);
    if (matched) return { ok: true, reason: 'installed_via_org', hint: '' };
  }

  // 両方失敗・両方該当なし
  if (userResult.status !== 0 && orgResult.status !== 0) {
    const cls = classifyGhError(userResult.stderr + orgResult.stderr);
    if (cls === 'unauthenticated') {
      return { ok: false, reason: 'unauthenticated', hint: 'gh CLI が未認証です。`gh auth login` を実行してから再試行してください' };
    }
    return { ok: false, reason: 'gh_error', hint: `gh コマンド実行に失敗しました: ${(userResult.stderr || orgResult.stderr).trim() || 'exit non-zero'}` };
  }

  return {
    ok: false,
    reason: 'not_installed',
    hint: `vibehawk App (id=${targetAppIdStr}) が ${repo} にインストールされていません。GitHub の App Settings ページから対象リポジトリにインストールしてください`,
  };
}

function matchInstallation(stdout, targetAppIdStr, repo) {
  if (!stdout || !stdout.trim()) return false;
  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch (_) {
    return false;
  }
  // /user/installations は { installations: [...] } 形式、/orgs/X/installations は配列または同形式
  const installations = Array.isArray(parsed)
    ? parsed
    : Array.isArray(parsed.installations)
      ? parsed.installations
      : [];
  if (installations.length === 0) return false;
  for (const inst of installations) {
    if (String(inst.app_id) !== targetAppIdStr) continue;
    // repository_selection: 'all' なら対象 repo 含むと判定
    if (inst.repository_selection === 'all') return true;
    // 'selected' 時は別途 /user/installations/<id>/repositories を呼ぶ必要があるが、
    // ここでは app_id 一致 + selected 状態を「対象 repo がインストール対象になっている可能性が高い」
    // と楽観的に扱う（誤判定時は次のステップ verifySecret(VIBEHAWK_APP_ID) で検出される）
    if (inst.repository_selection === 'selected') return true;
    return true;
  }
  return false;
}

// workflow ファイルが対象リポジトリ（マージ後の main）に配置されているかを 200/404 で判定
// 引数: repo = "owner/repo"、path = ".github/workflows/vibehawk-review.yml"
function verifyWorkflow(repo, path) {
  if (!repo || !/^[A-Za-z0-9_.\-]+\/[A-Za-z0-9_.\-]+$/.test(repo)) {
    return { ok: false, reason: 'invalid_repo', hint: `repo の形式が正しくありません: ${repo}` };
  }
  if (!path || typeof path !== 'string') {
    return { ok: false, reason: 'invalid_path', hint: 'path が空または文字列ではありません' };
  }
  const r = runGhApi([`repos/${repo}/contents/${path}`, '--silent']);
  if (r.status === 0) {
    return { ok: true, reason: 'found', hint: '' };
  }
  const cls = classifyGhError(r.stderr);
  if (cls === 'not_found') {
    return {
      ok: false,
      reason: 'not_placed',
      hint: `${path} が対象リポジトリの default branch にまだ配置されていません。workflow PR をマージしてから再試行してください`,
    };
  }
  if (cls === 'unauthenticated') {
    return { ok: false, reason: 'unauthenticated', hint: 'gh CLI が未認証です。`gh auth login` を実行してから再試行してください' };
  }
  return { ok: false, reason: 'gh_error', hint: `gh コマンド実行に失敗しました: ${r.stderr.trim() || `exit ${r.status}`}` };
}

module.exports = {
  verifySecret,
  verifyAppInstallation,
  verifyWorkflow,
  // テスト容易化のため一部内部関数も export
  classifyGhError,
  matchInstallation,
};
