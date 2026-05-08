'use strict';

// vibehawk GitHub App 命名統制（Issue #25）
//
// vibehawk は App 名を `vibehawk-for-<owner>` 形式で固定する。
// 利用者は名前を自由にカスタマイズできない。
//
// 設計根拠:
// - GitHub Apps はグローバルで名前ユニーク制約があり、`vibehawk[bot]` 単独では
//   先着 1 名しか作れない
// - `<owner>` 部分で名前空間を分離することで、すべての利用者がブランド `vibehawk` を
//   含む App 名を持てる
// - 全 bot 名に `vibehawk` を必ず含むことで、ブランドの一貫性を担保

const APP_NAME_PREFIX = 'vibehawk-for';

// GitHub user/org 名の制約: 1-39 文字、alphanumeric + ハイフン、先頭末尾はハイフン不可、連続ハイフン不可
const OWNER_PATTERN = /^[a-zA-Z0-9](?:[a-zA-Z0-9]|-(?=[a-zA-Z0-9])){0,38}$/;

function buildAppName(owner) {
  validateOwner(owner);
  return `${APP_NAME_PREFIX}-${owner}`;
}

function validateOwner(owner) {
  if (typeof owner !== 'string' || owner.length === 0) {
    throw new Error('vibehawk: owner 名が空です');
  }
  if (!OWNER_PATTERN.test(owner)) {
    throw new Error(
      `vibehawk: owner 名 '${owner}' が GitHub のユーザー/Org 命名規則に違反しています ` +
        '（1-39 文字、英数字とハイフン、先頭末尾はハイフン不可、連続ハイフン不可）'
    );
  }
  return true;
}

// CLI 引数 --owner=foo または --owner foo を解析
function parseOwnerArg(argv) {
  if (!Array.isArray(argv)) return null;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--owner' && i + 1 < argv.length) {
      return argv[i + 1].trim();
    }
    if (typeof arg === 'string' && arg.startsWith('--owner=')) {
      return arg.slice('--owner='.length).trim();
    }
  }
  return null;
}

module.exports = { APP_NAME_PREFIX, buildAppName, validateOwner, parseOwnerArg };
