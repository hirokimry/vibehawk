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

# Issue #25: 命名統制 — buildAppName が vibehawk-for-<owner> 形式
if node -e '
const { buildAppName } = require("./cli/naming");
const name = buildAppName("alice");
if (name !== "vibehawk-for-alice") { console.error("expected vibehawk-for-alice, got:", name); process.exit(1); }
'; then
  pass "buildAppName(alice) → vibehawk-for-alice"
else
  fail "buildAppName が vibehawk-for-<owner> 形式を返さない"
fi

# Issue #25: 命名統制 — invalid owner はエラー
for invalid in "" "-leading-hyphen" "trailing-hyphen-" "double--hyphen" "name_with_underscore" "12345678901234567890123456789012345678901"; do
  if node -e "
const { buildAppName } = require('./cli/naming');
try {
  buildAppName('${invalid}');
  process.exit(1);
} catch (e) {
  process.exit(0);
}
"; then
    pass "buildAppName('${invalid}') が拒否される"
  else
    fail "buildAppName('${invalid}') が拒否されない"
  fi
done

# Issue #25: 命名統制 — valid owner（連続ハイフンなし、先頭末尾英数字）は受理
for valid in "alice" "my-org" "user123" "Org-Name-1"; do
  if node -e "
const { buildAppName } = require('./cli/naming');
buildAppName('${valid}');
"; then
    pass "buildAppName('${valid}') が受理される"
  else
    fail "buildAppName('${valid}') が受理されない"
  fi
done

# Issue #25: 命名統制 — parseOwnerArg が --owner=foo / --owner foo を解析
if node -e '
const { parseOwnerArg } = require("./cli/naming");
if (parseOwnerArg(["--owner=alice"]) !== "alice") process.exit(1);
if (parseOwnerArg(["--owner", "bob"]) !== "bob") process.exit(1);
if (parseOwnerArg(["--other"]) !== null) process.exit(1);
'; then
  pass "parseOwnerArg が --owner / --owner= 両形式を解析"
else
  fail "parseOwnerArg の解析挙動が想定と異なる"
fi

# Issue #26: oauth.js が存在
if [[ -f cli/oauth.js ]]; then
  pass "cli/oauth.js が存在する"
else
  fail "cli/oauth.js が存在しない"
fi

# Issue #26: validateToken が形式違反トークンを拒否
if node -e '
const { validateToken } = require("./cli/oauth");
try { validateToken(""); process.exit(1); } catch (e) {}
try { validateToken("short"); process.exit(1); } catch (e) {}
try { validateToken("contains spaces in token here xxxxxxxxxx"); process.exit(1); } catch (e) {}
try { validateToken("ABCDEFG_HIJKLMN-1234567890.+/=ABCDEFG"); /* OK */ } catch (e) { process.exit(1); }
'; then
  pass "validateToken が形式違反を拒否、有効トークンを受理"
else
  fail "validateToken の挙動が想定と異なる"
fi

# Issue #26: parseRepoArg が --repo / --repo= 両形式を解析
if node -e '
const { parseRepoArg } = require("./cli/oauth");
if (parseRepoArg(["--repo=alice/bob"]) !== "alice/bob") process.exit(1);
if (parseRepoArg(["--repo", "alice/bob"]) !== "alice/bob") process.exit(1);
if (parseRepoArg(["--other"]) !== null) process.exit(1);
'; then
  pass "parseRepoArg が --repo / --repo= 両形式を解析"
else
  fail "parseRepoArg の挙動が想定と異なる"
fi

# Issue #26: oauth.js が外部 fetch を発行しないこと（Anthropic OAuth フローは委譲のみ）
if grep -E "fetch\\(['\"]" cli/oauth.js > /dev/null; then
  fail "oauth.js が外部 fetch を含む（公式 claude setup-token 委譲設計に反する）"
else
  pass "oauth.js は外部 fetch を持たず claude setup-token に委譲"
fi

# Issue #26: oauth.js がトークンをファイル書き込みしないこと
if grep -E "(writeFile|writeFileSync|fs\\.write)" cli/oauth.js > /dev/null; then
  fail "oauth.js がトークンをファイル書き込みしている可能性（メモリ上のみで保持すべき）"
else
  pass "oauth.js はトークンをファイル書き込みしない（メモリ上のみで保持）"
fi

# Issue #26: setup-token コマンドが index.js に登録されている
if grep -F "'setup-token':" cli/index.js > /dev/null; then
  pass "setup-token コマンドが index.js に登録されている"
else
  fail "setup-token コマンドが index.js に登録されていない"
fi

# Issue #26: help に setup-token が含まれる
if node cli/index.js help 2>&1 | grep -F "setup-token" > /dev/null; then
  pass "CLI help が setup-token コマンドを表示"
else
  fail "CLI help が setup-token コマンドを表示しない"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
