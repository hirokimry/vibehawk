#!/usr/bin/env bash
# vibehawk CLI の最小要件検証
# - cli/ のファイル存在
# - package.json の bin 定義
# - manifest.js の buildManifest が期待通りの形を返す
# - localhost のみで完結（外部 fetch URL が github.com / api.github.com に限定）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0

pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  FAILED=$((FAILED + 1))
}

echo "=== vibehawk CLI 検証 ==="

# 必須ファイル存在
for f in package.json cli/index.js cli/install.js cli/manifest.js; do
  if [[ -f "$f" ]]; then
    pass "$f が存在する"
  else
    fail "$f が存在しない"
  fi
done

# 前提ファイル不在なら後続テスト無意味
if [[ ! -f cli/install.js || ! -f cli/manifest.js || ! -f package.json ]]; then
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# package.json の bin 定義
if node -e 'const p = require("./package.json"); if (p.bin && p.bin.vibehawk) { process.exit(0); } else { process.exit(1); }'; then
  pass "package.json に bin.vibehawk が定義されている"
else
  fail "package.json に bin.vibehawk が定義されていない"
fi

# Node.js engine 要件
if node -e 'const p = require("./package.json"); const e = p.engines && p.engines.node; if (e && /\d/.test(e)) { process.exit(0); } else { process.exit(1); }'; then
  pass "package.json に engines.node が定義されている"
else
  fail "package.json に engines.node が定義されていない"
fi

# CLI index が executable
if [[ -x cli/index.js ]]; then
  pass "cli/index.js が executable"
else
  fail "cli/index.js が executable ではない"
fi

# CLI が shebang を持つ
if head -1 cli/index.js | grep -F '#!/usr/bin/env node' > /dev/null; then
  pass "cli/index.js に shebang がある"
else
  fail "cli/index.js に shebang がない"
fi

# manifest.js が localhost callback URL を生成すること
if node -e '
const { buildManifest } = require("./cli/manifest");
const m = buildManifest({ port: 8765, name: "vibehawk" });
if (m.redirect_url !== "http://localhost:8765/callback") { console.error("redirect_url mismatch:", m.redirect_url); process.exit(1); }
if (!Array.isArray(m.callback_urls) || m.callback_urls[0] !== "http://localhost:8765/callback") { console.error("callback_urls mismatch"); process.exit(1); }
'; then
  pass "manifest.js が localhost callback URL を生成"
else
  fail "manifest.js の callback URL が localhost ではない"
fi

# manifest.js が最小権限のみ要求すること
if node -e '
const { buildManifest } = require("./cli/manifest");
const m = buildManifest({ port: 8765, name: "vibehawk" });
const expected = ["pull_requests", "issues", "contents"];
const actual = Object.keys(m.default_permissions).sort();
if (JSON.stringify(actual) !== JSON.stringify(expected.sort())) { console.error("permissions:", actual); process.exit(1); }
if (m.default_permissions.pull_requests !== "write") process.exit(1);
if (m.default_permissions.issues !== "write") process.exit(1);
if (m.default_permissions.contents !== "read") process.exit(1);
'; then
  pass "manifest.js が最小権限（pull_requests:write, issues:write, contents:read）のみ要求"
else
  fail "manifest.js の最小権限が想定と異なる"
fi

# manifest.js が public: true（OSS 配布のため）
if node -e '
const { buildManifest } = require("./cli/manifest");
const m = buildManifest({ port: 8765, name: "vibehawk" });
if (m.public !== true) process.exit(1);
'; then
  pass "manifest.js が public: true"
else
  fail "manifest.js が public: true ではない"
fi

# install.js が vibehawk 運営側サーバーへ通信しないこと（github.com/api.github.com 以外の HTTP 呼び出しが無い）
if grep -E "fetch\\(['\"]" cli/install.js | grep -vE "(api\\.github\\.com|github\\.com)" > /dev/null; then
  fail "install.js が vibehawk 運営側サーバーに通信する fetch を含む"
else
  pass "install.js は localhost / github.com 以外への外部通信を含まない"
fi

# Private Key 取扱: install.js が PEM を REDACTED 化すること
if grep -F "credentials.pem = '[REDACTED" cli/install.js > /dev/null; then
  pass "install.js が Private Key を REDACTED 化（CISO Critical 条件）"
else
  fail "install.js が Private Key を REDACTED 化していない"
fi

# CLI help 表示
if node cli/index.js help 2>&1 | grep -F "npx vibehawk install" > /dev/null; then
  pass "CLI help が install コマンドを表示"
else
  fail "CLI help が install コマンドを表示しない"
fi

# version 表示
if node cli/index.js version 2>&1 | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" > /dev/null; then
  pass "CLI version が semver を表示"
else
  fail "CLI version が semver を表示しない"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
