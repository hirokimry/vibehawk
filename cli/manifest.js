'use strict';

// GitHub App Manifest Flow のマニフェスト定義
// https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest

const VIBEHAWK_REPO_URL = 'https://github.com/hirokimry/vibehawk';
// hook_attributes.url は GitHub manifest 仕様で必須だが、active: false で実送信を抑止する。
// .invalid は RFC 2606 で名前解決不可と定められた reserved TLD で、active が将来誤って
// true に変更されても DNS 解決段階で失敗するため、外部到達は二重に防がれる。
const NEVER_RESOLVED_WEBHOOK_URL = 'https://example.invalid/webhook';

// callback URL は localhost に固定（vibehawk 運営側サーバーには一切送信しない）
function buildManifest({ port, name }) {
  if (typeof port !== 'number' || port <= 0) {
    throw new Error('port must be a positive number');
  }
  if (!name || typeof name !== 'string') {
    throw new Error('name must be a non-empty string');
  }
  return {
    name,
    url: VIBEHAWK_REPO_URL,
    hook_attributes: { url: NEVER_RESOLVED_WEBHOOK_URL, active: false },
    redirect_url: `http://localhost:${port}/callback`,
    callback_urls: [`http://localhost:${port}/callback`],
    public: true,
    default_permissions: {
      pull_requests: 'write',
      issues: 'write',
      contents: 'read',
      // Issue #121-C1: status check による merge gating を仕様として有効化するための権限予約。
      // 注: 現行 workflow（templates/.github/workflows/vibehawk-review.yml）は status check の POST に
      // App Installation Token ではなく workflow デフォルトの GITHUB_TOKEN（permissions.checks: write 付き）
      // を使う設計（Issue #121-C1 fix）。新規 install 利用者の App には本権限が初期付与され、
      // 将来 App 経由で check-runs を扱う機能拡張時に再 install 不要となるため定義しておく。
      checks: 'write',
    },
    default_events: ['pull_request'],
  };
}

module.exports = { buildManifest, VIBEHAWK_REPO_URL, NEVER_RESOLVED_WEBHOOK_URL };
