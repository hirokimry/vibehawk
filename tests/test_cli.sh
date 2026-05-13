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

# Issue #26 / #74: oauth.js が存在
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

# Issue #26: parseRepoArg が --repo / --repo= 両形式を解析（URL 表示用に維持）
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

# Issue #26 / #74: oauth.js がトークンをファイル書き込みしないこと
if grep -E "(writeFile|writeFileSync|fs\\.write)" cli/oauth.js > /dev/null; then
  fail "oauth.js がトークンをファイル書き込みしている可能性（メモリ上のみで保持すべき）"
else
  pass "oauth.js はトークンをファイル書き込みしない（メモリ上のみで保持）"
fi

# Issue #74: oauth.js は gh secret set を呼び出さない（Issue #72 全手動方針）
# Issue #26 で実装した自動登録を撤去し、利用者が GitHub Settings UI で手動登録する経路に変更
if grep -E "secret['\"][[:space:]]*,[[:space:]]*['\"]set" cli/oauth.js > /dev/null; then
  fail "oauth.js が gh secret set 呼び出しを残している（Issue #72 / #74 全手動方針違反）"
else
  pass "oauth.js は gh secret set を呼び出さない（Issue #72 / #74 全手動方針）"
fi

# Issue #74: setSecret 関数が export から削除されている
if node -e '
const oauth = require("./cli/oauth");
process.exit(typeof oauth.setSecret === "undefined" ? 0 : 1);
'; then
  pass "oauth.js から setSecret が export されていない（撤去済み）"
else
  fail "oauth.js が setSecret を export している（Issue #74 撤去漏れ）"
fi

# Issue #74: buildSettingsUrl が正しい GitHub Settings URL を生成
if node -e '
const { buildSettingsUrl } = require("./cli/oauth");
if (buildSettingsUrl("alice/bob") !== "https://github.com/alice/bob/settings/secrets/actions/new") process.exit(1);
if (buildSettingsUrl(null) !== null) process.exit(1);
if (buildSettingsUrl("invalid_no_slash") !== null) process.exit(1);
if (buildSettingsUrl("a/b/c") !== null) process.exit(1);
'; then
  pass "buildSettingsUrl が正しい GitHub Settings URL を生成（不正入力も拒否）"
else
  fail "buildSettingsUrl の挙動が想定と異なる"
fi

# Issue #74: copyToClipboard が --body 等のプロセス引数に token を渡さないこと（stdin 経由のみ）
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/oauth.js", "utf8");
const m = src.match(/function copyToClipboard[\s\S]*?\n\}/);
if (!m) process.exit(1);
const body = m[0];
if (!/spawnSync\([^)]*input:\s*token/.test(body)) process.exit(1);
process.exit(0);
'; then
  pass "copyToClipboard は stdin 経由（spawnSync input オプション）で token を渡す"
else
  fail "copyToClipboard が token をプロセス引数経由で渡す可能性（CISO Critical 条件違反）"
fi

# Issue #74: setupToken は consent プロンプトを呼び、拒否時に clipboard を呼ばない
if node -e '
const oauth = require("./cli/oauth");
let consentCalled = false;
let clipboardCalled = false;
oauth.setupToken({
  argv: ["--repo", "alice/bob"],
  rlFactory: () => ({
    question: (q, cb) => {
      if (q.includes("貼り付けて")) cb("ABCDEFG_HIJKLMN-1234567890.+/=ABCDEFG");
      else cb("");
    },
    close: () => {},
  }),
  clipboard: () => { clipboardCalled = true; return { success: true }; },
  consent: async () => { consentCalled = true; return false; },
}).then((result) => {
  if (!consentCalled) { console.error("consent should be called"); process.exit(1); }
  if (clipboardCalled) { console.error("clipboard should not be called when consent denied"); process.exit(1); }
  if (result.repo !== "alice/bob") process.exit(1);
  if (result.settingsUrl !== "https://github.com/alice/bob/settings/secrets/actions/new") process.exit(1);
  if (result.clipboardCopied !== false) process.exit(1);
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "setupToken は consent プロンプトを呼び、拒否時に clipboard を呼ばない"
else
  fail "setupToken の consent プロンプト挙動が想定と異なる"
fi

# Issue #26 / #74: setup-token コマンドが index.js に登録されている
if grep -F "'setup-token':" cli/index.js > /dev/null; then
  pass "setup-token コマンドが index.js に登録されている"
else
  fail "setup-token コマンドが index.js に登録されていない"
fi

# Issue #26 / #74: help に setup-token が含まれる
if node cli/index.js help 2>&1 | grep -F "setup-token" > /dev/null; then
  pass "CLI help が setup-token コマンドを表示"
else
  fail "CLI help が setup-token コマンドを表示しない"
fi

# Issue #74: help が「secret を書き込まない」旨を表示する
if node cli/index.js help 2>&1 | grep -F "secret を書き込まない" > /dev/null; then
  pass "CLI help が secret 非書込みを明示"
else
  fail "CLI help が secret 非書込みを明示していない"
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

# Issue #59: Manifest Flow port hijacking / CSRF 対策 — state パラメータ生成
# crypto.randomBytes で cryptographically secure な state を生成していること
if grep -E "crypto\.randomBytes\([0-9]+\)\.toString\(['\"]hex['\"]\)" cli/install.js > /dev/null; then
  pass "install.js が crypto.randomBytes で state を生成（Issue #59 CSRF 対策）"
else
  fail "install.js が crypto.randomBytes で state を生成していない"
fi

# Issue #59: state を timing-safe に照合していること（crypto.timingSafeEqual）
if grep -F "crypto.timingSafeEqual" cli/install.js > /dev/null; then
  pass "install.js が crypto.timingSafeEqual で state を照合（Issue #59 CSRF 対策）"
else
  fail "install.js が crypto.timingSafeEqual で state を照合していない"
fi

# Issue #59: /start レスポンスに state hidden input が含まれ、/callback で state を検証することの動的検証
if node -e '
process.env.NODE_NO_WARNINGS = "1";
const http = require("http");
const install = require("./cli/install");
const { buildManifest } = require("./cli/manifest");
const PORT = 18765;
const manifest = buildManifest({ port: PORT, name: "vibehawk-for-test" });

// waitForCallback の Promise を即時 catch して unhandled rejection を抑止
const promise = install.waitForCallback({ port: PORT, manifest, openBrowser: () => {} });
let rejectionReason = null;
promise.catch((e) => { rejectionReason = e; });

function httpGet(path) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: "127.0.0.1", port: PORT, path }, (res) => {
      let data = "";
      res.on("data", (chunk) => data += chunk);
      res.on("end", () => resolve({ status: res.statusCode, body: data }));
    });
    req.on("error", reject);
  });
}

(async () => {
  // /start を叩いて HTML を取得し state を抽出
  const startRes = await httpGet("/start");
  if (startRes.status !== 200) throw new Error("/start status: " + startRes.status);
  if (!/<input[^>]*name="state"[^>]*value="[a-f0-9]+"/.test(startRes.body)) {
    throw new Error("/start HTML に state hidden input が含まれない");
  }
  const stateMatch = startRes.body.match(/<input[^>]*name="state"[^>]*value="([a-f0-9]+)"/);
  const state = stateMatch[1];
  if (state.length !== 64) throw new Error("state length unexpected: " + state.length);

  // 誤った state で /callback を叩く → 400 応答 + waitForCallback が reject される
  const badRes = await httpGet("/callback?code=dummy&state=deadbeef");
  if (badRes.status !== 400) throw new Error("/callback bad state status: " + badRes.status);

  // microtask を 1 ターン進めて rejection ハンドラを実行させる
  await new Promise((r) => setImmediate(r));
  if (!rejectionReason) throw new Error("waitForCallback should reject on state mismatch");
  if (!/state mismatch/.test(rejectionReason.message)) {
    throw new Error("expected state mismatch error, got: " + rejectionReason.message);
  }
  process.exit(0);
})().catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "Issue #59: /start に state hidden input が含まれ /callback で誤った state を 400 拒否 + reject"
else
  fail "Issue #59: state hidden input / state 検証の動的動作が想定と異なる"
fi

# Issue #59: 正しい state での /callback が code を resolve すること
if node -e '
process.env.NODE_NO_WARNINGS = "1";
const http = require("http");
const install = require("./cli/install");
const { buildManifest } = require("./cli/manifest");
const PORT = 18766;
const manifest = buildManifest({ port: PORT, name: "vibehawk-for-test" });

const promise = install.waitForCallback({ port: PORT, manifest, openBrowser: () => {} });

function httpGet(path) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: "127.0.0.1", port: PORT, path }, (res) => {
      let data = "";
      res.on("data", (chunk) => data += chunk);
      res.on("end", () => resolve({ status: res.statusCode, body: data }));
    });
    req.on("error", reject);
  });
}

(async () => {
  const startRes = await httpGet("/start");
  const stateMatch = startRes.body.match(/<input[^>]*name="state"[^>]*value="([a-f0-9]+)"/);
  const state = stateMatch[1];

  // 正しい state で /callback を叩く → 200 + waitForCallback が code を resolve
  const okRes = await httpGet("/callback?code=mycode123&state=" + state);
  if (okRes.status !== 200) throw new Error("/callback ok status: " + okRes.status);

  const code = await promise;
  if (code !== "mycode123") throw new Error("expected code mycode123, got: " + code);
  process.exit(0);
})().catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "Issue #59: 正しい state での /callback が code を resolve"
else
  fail "Issue #59: 正しい state での /callback resolve 挙動が想定と異なる"
fi

# Issue #58: parseOverwrite が --overwrite を検出
if node -e '
const { parseOverwrite } = require("./cli/install");
if (parseOverwrite(["--overwrite"]) !== true) process.exit(1);
if (parseOverwrite(["--owner", "alice", "--overwrite"]) !== true) process.exit(1);
if (parseOverwrite(["--owner", "alice"]) !== false) process.exit(1);
if (parseOverwrite([]) !== false) process.exit(1);
'; then
  pass "parseOverwrite が --overwrite を検出"
else
  fail "parseOverwrite の挙動が想定と異なる"
fi

# Issue #58: createWorkflowPr が export されている
if node -e '
const install = require("./cli/install");
if (typeof install.createWorkflowPr !== "function") process.exit(1);
if (install.WORKFLOW_PATH !== ".github/workflows/vibehawk-review.yml") process.exit(1);
if (typeof install.WORKFLOW_BRANCH !== "string" || install.WORKFLOW_BRANCH.length === 0) process.exit(1);
'; then
  pass "createWorkflowPr / WORKFLOW_PATH / WORKFLOW_BRANCH が export されている"
else
  fail "Issue #58 の export が想定と異なる"
fi

# Issue #58: --repo 指定時の --dry-run 出力に workflow PR 作成計画が表示される
dry_run_repo_output="$(node -e '
const install = require("./cli/install");
install.run({
  argv: ["--owner", "alice", "--repo", "alice/test-repo", "--dry-run"],
  openBrowser: () => {},
  readOwner: async () => "alice",
}).then(() => process.exit(0)).catch((e) => { console.error(e.message); process.exit(1); });
' 2>&1)"

if echo "$dry_run_repo_output" | grep -F "workflow PR 作成先: alice/test-repo" > /dev/null \
  && echo "$dry_run_repo_output" | grep -F "workflow ファイル配置 PR を作成" > /dev/null \
  && echo "$dry_run_repo_output" | grep -F "vibehawk-review.yml" > /dev/null \
  && echo "$dry_run_repo_output" | grep -F "vibehawk-chat.yml" > /dev/null \
  && echo "$dry_run_repo_output" | grep -F "GitHub Secrets への書き込み: なし" > /dev/null; then
  pass "--dry-run で --repo 指定時に 2 つの workflow PR 作成計画 (review + chat) と Secrets 非書込が表示される"
else
  fail "--dry-run + --repo の出力に必須要件（review + chat 両方 / Secrets 非書込み宣言）が含まれない"
fi

# Issue #58: --repo 指定時の --dry-run でも実際の workflow PR 作成（gh CLI 呼出）が起きない
if node -e '
process.env.NODE_NO_WARNINGS = "1";
const install = require("./cli/install");
let workflowPlacerCalled = false;
install.run({
  argv: ["--owner", "alice", "--repo", "alice/test-repo", "--dry-run"],
  openBrowser: () => {},
  readOwner: async () => "alice",
  workflowPlacer: () => { workflowPlacerCalled = true; return Promise.resolve({ url: "fake" }); },
}).then(() => {
  if (workflowPlacerCalled) { console.error("workflowPlacer should not run in dry-run"); process.exit(1); }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "--dry-run で workflowPlacer が呼ばれない"
else
  fail "--dry-run で workflowPlacer が呼ばれる可能性"
fi

# Issue #58: createWorkflowPr が --repo 形式を検証する（不正入力を拒否）
if node -e '
const { createWorkflowPr } = require("./cli/install");
createWorkflowPr({ repo: "invalid_no_slash" }).then(() => process.exit(1)).catch((e) => {
  if (!/形式が正しくありません/.test(e.message)) process.exit(1);
  process.exit(0);
});
'; then
  pass "createWorkflowPr が --repo 形式不正を拒否"
else
  fail "createWorkflowPr が不正な --repo を受け付ける可能性"
fi

# Issue #58: install.js が外部 fetch する URL は GitHub 公式エンドポイントのみ
# （vibehawk 運営側サーバーへの通信禁止 + actions/create-github-app-token 等 GitHub Apps 関連 URL のみ）
if grep -E "fetch\\(['\"]https://[^'\"]*['\"]" cli/install.js | grep -v -E "github\\.com|githubusercontent\\.com" > /dev/null; then
  fail "install.js に GitHub 公式以外の fetch URL が含まれる（vibehawk 運営側サーバー通信禁止違反の可能性）"
else
  pass "install.js の外部 fetch URL は GitHub 公式エンドポイントのみ"
fi

# Issue #58 / #74: install.js が gh secret set を呼び出さない（CLI は secret を一切 touch しない）
if grep -E "gh.*secret.*set|secret['\"][[:space:]]*,[[:space:]]*['\"]set" cli/install.js > /dev/null; then
  fail "install.js が gh secret set を呼び出している（Issue #72 / #74 全手動方針違反）"
else
  pass "install.js は gh secret set を呼び出さない（Issue #72 / #74 全手動方針）"
fi

# Issue #58: install help が --repo フラグを表示
if node cli/index.js help 2>&1 | grep -F "install [--repo OWNER/REPO]" > /dev/null; then
  pass "CLI help が install --repo フラグを表示"
else
  fail "CLI help が install --repo フラグを表示しない"
fi

# Issue #61: install --dry-run の同意プレビューに Anthropic 送信通知が含まれること
# (POLICY.md データ取扱い方針との整合 + GDPR / 個人情報保護法対応の利用者事前告知)
anthropic_notice_output="$(node -e '
const install = require("./cli/install");
install.run({
  argv: ["--owner", "alice", "--dry-run"],
  openBrowser: () => {},
  readOwner: async () => "alice",
}).then(() => process.exit(0)).catch((e) => { console.error(e.message); process.exit(1); });
' 2>&1)"

if echo "$anthropic_notice_output" | grep -F "Anthropic への送信について" > /dev/null \
  && echo "$anthropic_notice_output" | grep -F "claude-code-action" > /dev/null \
  && echo "$anthropic_notice_output" | grep -F "利用者の Anthropic 契約" > /dev/null \
  && echo "$anthropic_notice_output" | grep -F "docs/POLICY.md" > /dev/null; then
  pass "install --dry-run の同意プレビューに Anthropic 送信通知が含まれる（Issue #61）"
else
  fail "install --dry-run の同意プレビューに Anthropic 送信通知が含まれない"
fi

# Issue #60 / CEO 判断 B（2026-05-09）: assertCanonicalAppName 単体テスト
# 連番命名検出時にエラー終了する仕様（POLICY.md MUST 違反防止）
if node -e '
const { assertCanonicalAppName } = require("./cli/install");
// 正常名 → throw されない
const ok = { name: "vibehawk-for-alice", pem: "secret", slug: "vibehawk-for-alice", id: 1 };
assertCanonicalAppName(ok, "vibehawk-for-alice");
// 連番命名 → throw + redact
const ng = { name: "vibehawk-for-alice-2", pem: "PRIVATE", slug: "vibehawk-for-alice-2", id: 2 };
try {
  assertCanonicalAppName(ng, "vibehawk-for-alice");
  process.exit(1);
} catch (e) {
  if (!/命名統制衝突/.test(e.message)) process.exit(1);
  if (!/既存/.test(e.message)) process.exit(1);
  if (!/別の owner|別の名前/.test(e.message)) process.exit(1);
  // throw 経路でも Private Key が redact されていることを検証（CISO Critical）
  if (ng.pem !== "[REDACTED — vibehawk CLI does not expose Private Key]") process.exit(1);
}
// 空 expectedAppName → throw されない（ガード）
assertCanonicalAppName({ name: "any" }, null);
assertCanonicalAppName({ name: "any" }, "");
// credentials null/undefined → throw されない（ガード）
assertCanonicalAppName(null, "anything");
assertCanonicalAppName(undefined, "anything");
process.exit(0);
'; then
  pass "assertCanonicalAppName が連番命名で throw + Private Key redact、正常名/空入力で throw なし"
else
  fail "assertCanonicalAppName の挙動が想定と異なる"
fi

# Issue #60: install.run() が連番命名 credentials を返した場合に reject される（統合テスト）
# fetch をモックして exchangeCode が連番名 credentials を返す状況を再現
if node -e '
process.env.NODE_NO_WARNINGS = "1";
const install = require("./cli/install");
// fetch をモック: exchangeCode が連番名 credentials を返すように差し替え
global.fetch = async () => ({
  ok: true,
  json: async () => ({
    id: 999,
    name: "vibehawk-for-alice-2",
    slug: "vibehawk-for-alice-2",
    html_url: "https://github.com/apps/vibehawk-for-alice-2",
    pem: "FAKE_PRIVATE_KEY_DATA",
    client_secret: "FAKE_CLIENT_SECRET",
    webhook_secret: "FAKE_WEBHOOK_SECRET",
  }),
});
// waitForCallback もモック（HTTP server を起動させない）
const path = require("path");
const installPath = require.resolve("./cli/install");
delete require.cache[installPath];
const orig = require("./cli/install");
orig.waitForCallback = async () => "fake-code";
// orig.run は内部の waitForCallback を直接参照しているため、module を直接書き換えるのは難しい
// 代わりに waitForCallback の代替を passed in する設計がないので、HTTP server を立てる代わりに
// process を hang させずに済むよう、別アプローチ: assertCanonicalAppName を直接テスト済みなので
// 統合テストは waitForCallback / openBrowser を no-op に置換した dry-run 経路ではなく、
// fetch モックのみで run() の throw が起きるかを検証する
const http = require("http");
// HTTP server を立てる代わりに /callback への即時 GET を模倣するために、
// install.waitForCallback を直接シミュレートできないので、ここでは
// 「fetch モック下で exchangeCode → assertCanonicalAppName で throw」の連鎖を検証する
(async () => {
  try {
    const code = "fake-code";
    const credentials = await orig.exchangeCode(code);
    if (credentials.name !== "vibehawk-for-alice-2") process.exit(1);
    try {
      orig.assertCanonicalAppName(credentials, "vibehawk-for-alice");
      process.exit(1); // throw されなかった
    } catch (e) {
      if (!/命名統制衝突/.test(e.message)) process.exit(1);
      if (credentials.pem !== "[REDACTED — vibehawk CLI does not expose Private Key]") process.exit(1);
      process.exit(0);
    }
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
})();
' > /dev/null 2>&1; then
  pass "exchangeCode → assertCanonicalAppName の連鎖で連番命名が reject される（fetch モック統合テスト）"
else
  fail "exchangeCode → assertCanonicalAppName の連鎖が想定通りに動かない"
fi

# Issue #60: install.run() の正常名フローでは throw されないことの回帰確認
# （dry-run でなく実際の run() を走らせると HTTP server を起動するため、
#  ここでは「正常名でも assertCanonicalAppName が throw しない」ことを直接確認する）
if node -e '
const { assertCanonicalAppName } = require("./cli/install");
const ok = { name: "vibehawk-for-alice", pem: "secret", slug: "vibehawk-for-alice", id: 1 };
assertCanonicalAppName(ok, "vibehawk-for-alice");
process.exit(0);
'; then
  pass "正常名（vibehawk-for-<owner>）では assertCanonicalAppName が throw しない（回帰）"
else
  fail "正常名で assertCanonicalAppName が誤って throw する"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
