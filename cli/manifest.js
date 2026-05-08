'use strict';

// GitHub App Manifest Flow のマニフェスト定義
// https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest

const VIBEHAWK_REPO_URL = 'https://github.com/hirokimry/vibehawk';

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
    hook_attributes: { active: false },
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

module.exports = { buildManifest, VIBEHAWK_REPO_URL };
