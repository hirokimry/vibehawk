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

# package.json の bin.vibehawk が ./cli/index.js を指すこと（要件厳格化、誤設定を通さない）
if node -e 'const p = require("./package.json"); process.exit(p.bin && p.bin.vibehawk === "./cli/index.js" ? 0 : 1);'; then
  pass "package.json bin.vibehawk が ./cli/index.js を指す"
else
  fail "package.json bin.vibehawk が ./cli/index.js を指していない"
fi

# Node.js engine が >=18 を要求すること（要件厳格化）
if node -e 'const p = require("./package.json"); const e = p.engines && p.engines.node; process.exit(e && /^>=\s*18\b/.test(e) ? 0 : 1);'; then
  pass "package.json engines.node が >=18 を満たす"
else
  fail "package.json engines.node が >=18 を満たさない"
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

# install.js が GitHub 公式 manifest conversion エンドポイントのみを呼ぶこと
# - シングル/ダブル/バッククォート 3 形式の fetch 呼び出しを拾う
# - 許可: api.github.com/app-manifests/<code>/conversions のみ
fetch_calls="$(grep -nE "fetch\\([\"'\\\`]" cli/install.js || true)"
if [[ -z "$fetch_calls" ]]; then
  fail "install.js に fetch 呼び出しがない（manifest conversion が必要）"
else
  # 許可されたエンドポイント以外への fetch を検出すれば fail
  if echo "$fetch_calls" | grep -vE "api\\.github\\.com/app-manifests/[^/\"'\\\`]+/conversions" > /dev/null; then
    fail "install.js に manifest conversion 以外のエンドポイントへの fetch が含まれる"
  else
    pass "install.js の fetch は GitHub 公式 manifest conversion エンドポイントのみ"
  fi
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

# Issue #26: setup-token は CLAUDE_CODE_OAUTH_TOKEN のみを書き込み、他 secret を書き込まないこと
# - gh secret set 呼び出しが CLAUDE_CODE_OAUTH_TOKEN を含む
# - その呼び出し以外に gh secret set が存在しない（他 secret を勝手に書かない）
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/oauth.js", "utf8");
// execFileSync("gh", ["secret", "set", "CLAUDE_CODE_OAUTH_TOKEN", ...]) パターンを検出
const ok = /execFileSync\([^)]*["'"'"'`]gh["'"'"'`][^)]*["'"'"'`]secret["'"'"'`][^)]*["'"'"'`]set["'"'"'`][^)]*["'"'"'`]CLAUDE_CODE_OAUTH_TOKEN["'"'"'`]/.test(src);
process.exit(ok ? 0 : 1);
'; then
  pass "oauth.js が gh secret set CLAUDE_CODE_OAUTH_TOKEN を呼ぶ"
else
  fail "oauth.js に gh secret set CLAUDE_CODE_OAUTH_TOKEN の呼び出しがない"
fi

# secret set 呼び出しの数: gh + secret + set + CLAUDE_CODE_OAUTH_TOKEN の組合せが 1 つだけであること
# （他の secret を書く execFileSync が混入していないことを検証）
secret_set_count=$(grep -cE "secret['\"][[:space:]]*,[[:space:]]*['\"]set" cli/oauth.js || true)
if [[ "$secret_set_count" -eq 1 ]]; then
  pass "oauth.js の secret set 呼び出しは 1 箇所のみ（他 secret を書かない）"
else
  fail "oauth.js の secret set 呼び出し数が想定外: $secret_set_count（1 箇所のみであるべき）"
fi

# 念のため: CLAUDE_CODE_OAUTH_TOKEN 以外の secret 名が secret/set 引数列の近傍に出現しないこと
if grep -E "secret['\"][[:space:]]*,[[:space:]]*['\"]set" cli/oauth.js | grep -v "CLAUDE_CODE_OAUTH_TOKEN" > /dev/null; then
  fail "oauth.js が CLAUDE_CODE_OAUTH_TOKEN 以外の secret を書き込む可能性"
else
  pass "oauth.js は CLAUDE_CODE_OAUTH_TOKEN 以外の secret を書き込まない"
fi

# Issue #26: setSecret は --body フラグ経由でトークンを渡してはならない
# （プロセス引数への露出を防ぐため、stdin/input オプション経由を要求）
if grep -F "'--body'" cli/oauth.js > /dev/null || grep -F '"--body"' cli/oauth.js > /dev/null; then
  fail "oauth.js が gh secret set に --body フラグを使用（プロセス引数にトークンが露出する）"
else
  pass "oauth.js は gh secret set に --body フラグを使わず stdin 経由でトークンを渡す"
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

# Issue #27: parseDryRun が --dry-run を検出
if node -e '
const { parseDryRun } = require("./cli/install");
if (parseDryRun(["--dry-run"]) !== true) process.exit(1);
if (parseDryRun(["--owner", "alice", "--dry-run"]) !== true) process.exit(1);
if (parseDryRun(["--owner", "alice"]) !== false) process.exit(1);
if (parseDryRun([]) !== false) process.exit(1);
'; then
  pass "parseDryRun が --dry-run を検出"
else
  fail "parseDryRun の挙動が想定と異なる"
fi

# Issue #27: --dry-run 実行で実際の操作（HTTP server / browser / GitHub API）が起動しないこと
if node -e '
process.env.NODE_NO_WARNINGS = "1";
const install = require("./cli/install");
let httpServerStarted = false;
let browserOpened = false;
let fetchCalled = false;
const originalFetch = global.fetch;
global.fetch = () => { fetchCalled = true; return Promise.reject(new Error("should not be called")); };
const originalCreateServer = require("http").createServer;
require("http").createServer = function() { httpServerStarted = true; return originalCreateServer.apply(this, arguments); };
install.run({
  argv: ["--owner", "alice", "--dry-run"],
  openBrowser: () => { browserOpened = true; },
  readOwner: async () => "alice",
}).then((result) => {
  if (httpServerStarted) { console.error("http server should not start in dry-run"); process.exit(1); }
  if (browserOpened) { console.error("browser should not open in dry-run"); process.exit(1); }
  if (fetchCalled) { console.error("fetch should not be called in dry-run"); process.exit(1); }
  if (!result.dryRun) { console.error("result.dryRun should be true"); process.exit(1); }
  if (result.appName !== "vibehawk-for-alice") { console.error("appName mismatch"); process.exit(1); }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "--dry-run で HTTP server / browser / fetch が起動しない"
else
  fail "--dry-run で実際の操作が走る可能性"
fi

# Issue #27: --dry-run 出力に「実行計画 / 通信先 / 書き込み範囲」が表示されること
# （README.md / docs/POLICY.md の必須要件: 実変更なしで実行計画/通信先/書き込み範囲だけ表示）
dry_run_output="$(node -e '
const install = require("./cli/install");
install.run({
  argv: ["--owner", "alice", "--dry-run"],
  openBrowser: () => {},
  readOwner: async () => "alice",
}).then(() => process.exit(0)).catch((e) => { console.error(e.message); process.exit(1); });
' 2>&1)"

if echo "$dry_run_output" | grep -F "実行予定プレビュー" > /dev/null \
  && echo "$dry_run_output" | grep -F "localhost" > /dev/null \
  && echo "$dry_run_output" | grep -F "vibehawk 運営側サーバーへの通信" > /dev/null \
  && echo "$dry_run_output" | grep -F "ローカルファイルへの書き込み" > /dev/null \
  && echo "$dry_run_output" | grep -F "vibehawk-for-alice" > /dev/null; then
  pass "--dry-run 出力に実行計画・通信先・書き込み範囲・App 名が表示される"
else
  fail "--dry-run 出力に必須要件（実行計画・通信先・書き込み範囲・App 名）が含まれない"
fi

# Issue #28: parseYes が --yes / -y を検出
if node -e '
const { parseYes } = require("./cli/install");
if (parseYes(["--yes"]) !== true) process.exit(1);
if (parseYes(["-y"]) !== true) process.exit(1);
if (parseYes(["--owner", "alice"]) !== false) process.exit(1);
if (parseYes([]) !== false) process.exit(1);
'; then
  pass "parseYes が --yes / -y を検出"
else
  fail "parseYes の挙動が想定と異なる"
fi

# Issue #28: 同意拒否時に HTTP server / browser / fetch が起動しないこと
if node -e '
process.env.NODE_NO_WARNINGS = "1";
const install = require("./cli/install");
let httpServerStarted = false;
let browserOpened = false;
let fetchCalled = false;
global.fetch = () => { fetchCalled = true; return Promise.reject(new Error("should not be called")); };
const originalCreateServer = require("http").createServer;
require("http").createServer = function() { httpServerStarted = true; return originalCreateServer.apply(this, arguments); };
install.run({
  argv: ["--owner", "alice"],
  openBrowser: () => { browserOpened = true; },
  readOwner: async () => "alice",
  readConsent: async () => false,
}).then((result) => {
  if (httpServerStarted) { console.error("http server should not start when consent denied"); process.exit(1); }
  if (browserOpened) { console.error("browser should not open when consent denied"); process.exit(1); }
  if (fetchCalled) { console.error("fetch should not be called when consent denied"); process.exit(1); }
  if (!result.canceled) { console.error("result.canceled should be true"); process.exit(1); }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "同意拒否時に HTTP server / browser / fetch が起動しない"
else
  fail "同意拒否時に実際の操作が走る可能性"
fi

# Issue #28: --yes フラグで consent prompt がスキップされること（readConsent が呼ばれない）
if node -e '
process.env.NODE_NO_WARNINGS = "1";
const install = require("./cli/install");
let consentCalled = false;
install.run({
  argv: ["--owner", "alice", "--yes", "--dry-run"],
  openBrowser: () => {},
  readOwner: async () => "alice",
  readConsent: async () => { consentCalled = true; return true; },
}).then((result) => {
  if (consentCalled) { console.error("readConsent should not be called with --yes"); process.exit(1); }
  if (!result.dryRun) process.exit(1);
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "--yes で consent prompt がスキップされる"
else
  fail "--yes で consent prompt が呼ばれる"
fi

# Issue #31: install.js に Windows ブラウザ起動コマンド (cmd /c start) が定義されている
if grep -F "process.platform === 'win32'" cli/install.js > /dev/null && grep -F "'/c', 'start'" cli/install.js > /dev/null; then
  pass "install.js が Windows 用ブラウザ起動 (cmd /c start) を実装"
else
  fail "install.js に Windows 用ブラウザ起動が実装されていない"
fi

# Issue #31: install.js の path 操作が OS 非依存（path.sep への依存がないこと）
if grep -E "path\\.sep|\\\\\\\\|process.platform === 'win32'" cli/install.js | grep -v "process.platform === 'win32'" > /dev/null; then
  fail "install.js に OS 依存のパス区切り文字が残っている"
else
  pass "install.js に OS 依存のパス区切り文字がない"
fi

# Issue #31: localhost サーバーが '127.0.0.1' を listen（Windows IPv6/IPv4 デュアルスタック対応）
if grep -F "server.listen(port, '127.0.0.1'" cli/install.js > /dev/null; then
  pass "install.js が 127.0.0.1 を明示 listen（Windows IPv6 デュアルスタック対応）"
else
  fail "install.js が 127.0.0.1 を明示 listen していない（Windows で IPv6 にバインドされる可能性）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
