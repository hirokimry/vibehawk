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
    },
    default_events: ['pull_request'],
  };
}

module.exports = { buildManifest, VIBEHAWK_REPO_URL, NEVER_RESOLVED_WEBHOOK_URL };
