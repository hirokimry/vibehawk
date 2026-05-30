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
  const result = spawnSync('gh', ['api', ...args], { encoding: 'utf8' });
  return {
    status: result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
  };
}

function classifyGhError(stderr) {
  if (/\b404\b/.test(stderr)) return 'not_found';
  if (/\b401\b/.test(stderr)) return 'unauthenticated';
  if (/\b403\b/.test(stderr)) return 'forbidden';
  if (/\b5\d\d\b/.test(stderr)) return 'server_error';
  return 'unknown';
}

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

// /repos/:owner/:repo/installation は GitHub App 認証専用エンドポイントのため利用者 PAT では呼べない。
// 代替として /user/installations および /orgs/<org>/installations を使い app_id 一致 + repo 包含を確認する。
function verifyAppInstallation(repo, appId) {
  if (!repo || !/^[A-Za-z0-9_.\-]+\/[A-Za-z0-9_.\-]+$/.test(repo)) {
    return { ok: false, reason: 'invalid_repo', hint: `repo の形式が正しくありません: ${repo}` };
  }
  if (!Number.isInteger(appId)) {
    throw new TypeError(`vibehawk: appId は整数である必要があります（受領値: ${typeof appId} ${String(appId)}）`);
  }
  const targetAppIdStr = String(appId);
  const [owner] = repo.split('/');

  const userResult = runGhApi(['/user/installations', '--paginate']);
  if (userResult.status === 0) {
    const inst = matchInstallation(userResult.stdout, targetAppIdStr);
    if (inst) {
      const v = verifyRepoIncluded(inst, repo);
      if (v.ok) return { ok: true, reason: 'installed_via_user', hint: '' };
      // selected 状態で対象 repo 未包含が判明した場合は明確な hint を返す
      if (v.reason === 'repo_not_in_selection') {
        return {
          ok: false,
          reason: 'repo_not_in_selection',
          hint: `vibehawk App (id=${targetAppIdStr}) はインストール済みですが、${repo} がインストール対象に含まれていません。GitHub の App Settings ページで対象リポジトリを追加してください`,
        };
      }
      // 検証 API 失敗時はフォールバック（後段の verifySecret で実質検出される）
    }
  }

  const orgResult = runGhApi([`/orgs/${owner}/installations`, '--paginate']);
  if (orgResult.status === 0) {
    const inst = matchInstallation(orgResult.stdout, targetAppIdStr);
    if (inst) {
      const v = verifyRepoIncluded(inst, repo);
      if (v.ok) return { ok: true, reason: 'installed_via_org', hint: '' };
      if (v.reason === 'repo_not_in_selection') {
        return {
          ok: false,
          reason: 'repo_not_in_selection',
          hint: `vibehawk App (id=${targetAppIdStr}) はインストール済みですが、${repo} がインストール対象に含まれていません。GitHub の App Settings ページで対象リポジトリを追加してください`,
        };
      }
    }
  }

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

// テスト容易化のため pure 関数として分離（gh api を呼ばない）
function matchInstallation(stdout, targetAppIdStr) {
  if (!stdout || !stdout.trim()) return null;
  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch (_) {
    return null;
  }
  // /user/installations は { installations: [...] } 形式、/orgs/X/installations は配列または同形式
  const installations = Array.isArray(parsed)
    ? parsed
    : Array.isArray(parsed.installations)
      ? parsed.installations
      : [];
  if (installations.length === 0) return null;
  for (const inst of installations) {
    if (String(inst.app_id) === targetAppIdStr) return inst;
  }
  return null;
}

// 'selected' 時の楽観判定は廃止し /user/installations/<id>/repositories で実検証する
// （CISO 修正必須 1: 楽観判定を抜ける攻撃経路の閉塞）
function verifyRepoIncluded(installation, repo) {
  if (!installation || typeof installation !== 'object') {
    return { ok: false, reason: 'invalid_installation' };
  }
  if (installation.repository_selection === 'all') {
    return { ok: true, reason: 'all' };
  }
  if (installation.repository_selection !== 'selected') {
    // 未知の selection 値はフォールバックで楽観判定（後段の verifySecret で検出）
    return { ok: false, reason: 'verify_api_failed' };
  }
  const installationId = installation.id;
  if (!Number.isInteger(installationId)) {
    return { ok: false, reason: 'invalid_installation' };
  }
  const r = runGhApi([`/user/installations/${installationId}/repositories`, '--paginate']);
  if (r.status !== 0) {
    return { ok: false, reason: 'verify_api_failed' };
  }
  let parsed;
  try {
    parsed = JSON.parse(r.stdout);
  } catch (_) {
    return { ok: false, reason: 'verify_api_failed' };
  }
  const repos = Array.isArray(parsed)
    ? parsed
    : Array.isArray(parsed.repositories)
      ? parsed.repositories
      : [];
  const targetFullName = repo;
  const matched = repos.some((r) => r && typeof r.full_name === 'string' && r.full_name.toLowerCase() === targetFullName.toLowerCase());
  if (matched) {
    return { ok: true, reason: 'selected_includes_repo' };
  }
  return { ok: false, reason: 'repo_not_in_selection' };
}

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
  verifyRepoIncluded,
};
