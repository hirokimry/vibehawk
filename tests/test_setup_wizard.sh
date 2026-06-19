#!/usr/bin/env bash
# Issue #91: vibehawk setup 対話型ウィザードの最小要件検証
# - 配線（cli/setup.js / cli/verify.js / index.js への登録）
# - CISO Critical 機械検証（gh secret set 不在 / 書込系 gh api 不在 / 外部 fetch 不在 / stdin 経由 clipboard）
# - verify.js 異常系（401/403/404/spawn 失敗 / appId 型サニタイズ）
# - REDACT 強制化（install.run({ skipPrintResult: true }) 戻り値）
# - 状態遷移（@clack/prompts は require.cache 差し替えでモック）
# - 後方互換（headless オプション無しでの既存挙動）

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

echo "=== vibehawk setup ウィザード検証 (Issue #91) ==="

for f in cli/setup.js cli/verify.js; do
  if [[ -f "$f" ]]; then
    pass "$f が存在する"
  else
    fail "$f が存在しない"
  fi
done

if [[ ! -f cli/setup.js || ! -f cli/verify.js ]]; then
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# index.js に setup サブコマンドが登録されている
if grep -F "setup: ()" cli/index.js > /dev/null; then
  pass "setup コマンドが index.js に登録されている"
else
  fail "setup コマンドが index.js に登録されていない"
fi

# help に setup が表示される
if node cli/index.js help 2>&1 | grep -F "npx vibehawk setup" > /dev/null; then
  pass "CLI help が setup コマンドを表示"
else
  fail "CLI help が setup コマンドを表示しない"
fi

# CISO Critical: setup.js / verify.js が gh secret set を呼ばない（コメント / docstring を除外）
for f in cli/setup.js cli/verify.js; do
  # 行頭が // または * のコメント行を除外したうえで grep
  if grep -vE '^\s*(//|\*)' "$f" | grep -E "spawnSync\(['\"]gh['\"][^)]*secret[^)]*set|exec[a-zA-Z]*\(['\"]gh secret set" > /dev/null; then
    fail "$f が gh secret set を呼び出している（CISO Critical 違反）"
  else
    pass "$f は gh secret set を呼び出さない（CISO Critical）"
  fi
done

# CISO Critical: setup.js / verify.js が --method PUT/POST/DELETE を呼ばない（コメント除外）
for f in cli/setup.js cli/verify.js; do
  if grep -vE '^\s*(//|\*)' "$f" | grep -E "['\"]--method['\"][[:space:]]*,[[:space:]]*['\"](PUT|POST|DELETE)['\"]" > /dev/null; then
    fail "$f が --method PUT/POST/DELETE を呼び出している（CISO Critical 違反）"
  else
    pass "$f は --method PUT/POST/DELETE を呼び出さない（CISO Critical）"
  fi
done

# CISO Critical: setup.js が外部 fetch を持たない
if grep -E "fetch\\(['\"]" cli/setup.js > /dev/null; then
  fail "cli/setup.js が外部 fetch を含む（運営側サーバー通信禁止違反）"
else
  pass "cli/setup.js は外部 fetch を持たない（運営側サーバー通信禁止）"
fi

# CISO Critical: setup.js が clipboard を oauth.copyToClipboard 経由（stdin 経由）で扱う
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/setup.js", "utf8");
// tryClipboardCopy が oauth.copyToClipboard を呼んでいることを確認
if (!/oauth\.copyToClipboard\(/.test(src)) process.exit(1);
process.exit(0);
'; then
  pass "setup.js の clipboard 経路は oauth.copyToClipboard 流用（stdin 経由が継承される）"
else
  fail "setup.js が独自の clipboard 経路を持つ可能性（stdin 経由の継承を機械確認できない）"
fi

# CISO Critical: isSensitive: true の値が stdout に出ない（クリップボードフォールバック分岐）
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/setup.js", "utf8");
// showClipboardFallback 関数が isSensitive で分岐し、true 時に value を埋め込まないこと
const m = src.match(/function showClipboardFallback[\s\S]*?\n\}/);
if (!m) { console.error("showClipboardFallback not found"); process.exit(1); }
const body = m[0];
// isSensitive 分岐があること
if (!/isSensitive/.test(body)) { console.error("no isSensitive branch"); process.exit(1); }
// isSensitive: true 経路で value を文字列補間していないことを正規表現で確認
// （isSensitive: true 側は固定文字列の note のみで、value を埋めない）
const sensitive = body.match(/if\s*\(\s*isSensitive\s*\)[\s\S]*?else/);
if (!sensitive) { console.error("isSensitive branch structure invalid"); process.exit(1); }
const sensitiveBlock = sensitive[0];
if (/\$\{value\}/.test(sensitiveBlock)) { console.error("value template literal in isSensitive branch"); process.exit(1); }
process.exit(0);
'; then
  pass "showClipboardFallback の isSensitive: true 経路で value を stdout に出さない（CISO Critical）"
else
  fail "showClipboardFallback が isSensitive: true で value を stdout に出す可能性（CISO Critical 違反）"
fi

# verify.js: verifySecret が形式不正を拒否
if node -e '
const v = require("./cli/verify");
const r1 = v.verifySecret("invalid_no_slash", "FOO");
if (r1.ok || r1.reason !== "invalid_repo") process.exit(1);
const r2 = v.verifySecret("alice/bob", "");
if (r2.ok || r2.reason !== "invalid_secret_name") process.exit(1);
'; then
  pass "verifySecret が repo / secretName の形式不正を拒否"
else
  fail "verifySecret の形式不正拒否が想定と異なる"
fi

# verify.js: classifyGhError が 404/401/403/5xx を分類
if node -e '
const v = require("./cli/verify");
if (v.classifyGhError("HTTP 404: Not Found") !== "not_found") process.exit(1);
if (v.classifyGhError("HTTP 401: Unauthorized") !== "unauthenticated") process.exit(1);
if (v.classifyGhError("HTTP 403: Forbidden") !== "forbidden") process.exit(1);
if (v.classifyGhError("HTTP 502: Bad Gateway") !== "server_error") process.exit(1);
if (v.classifyGhError("some other error") !== "unknown") process.exit(1);
'; then
  pass "classifyGhError が 404/401/403/5xx/unknown を分類"
else
  fail "classifyGhError の分類が想定と異なる"
fi

# verify.js: matchInstallation が installation オブジェクトを返す（pure 関数、gh api 呼び出しなし）
if node -e '
const v = require("./cli/verify");
// 一致 → installation オブジェクトを返す
const j1 = JSON.stringify({ installations: [{ id: 1, app_id: 12345, repository_selection: "all" }] });
const inst1 = v.matchInstallation(j1, "12345");
if (!inst1 || inst1.app_id !== 12345 || inst1.repository_selection !== "all") process.exit(1);
// 一致 + selected
const j2 = JSON.stringify({ installations: [{ id: 2, app_id: 99999, repository_selection: "selected" }] });
const inst2 = v.matchInstallation(j2, "99999");
if (!inst2 || inst2.app_id !== 99999) process.exit(1);
// 不一致 → null
const j3 = JSON.stringify({ installations: [{ id: 3, app_id: 11111, repository_selection: "all" }] });
if (v.matchInstallation(j3, "12345") !== null) process.exit(1);
// 空配列 → null
if (v.matchInstallation(JSON.stringify({ installations: [] }), "12345") !== null) process.exit(1);
// 配列形式（/orgs/X/installations の場合） → installation を返す
const j4 = JSON.stringify([{ id: 4, app_id: 12345, repository_selection: "all" }]);
const inst4 = v.matchInstallation(j4, "12345");
if (!inst4 || inst4.id !== 4) process.exit(1);
// 不正な JSON → null
if (v.matchInstallation("not json", "12345") !== null) process.exit(1);
// 空文字 → null
if (v.matchInstallation("", "12345") !== null) process.exit(1);
'; then
  pass "matchInstallation が installation オブジェクト or null を返す（pure 関数）"
else
  fail "matchInstallation の挙動が想定と異なる"
fi

# verify.js: verifyRepoIncluded が repository_selection に基づき判定（CISO 修正必須 1）
if node -e '
const v = require("./cli/verify");
// repository_selection: all → ok
const r1 = v.verifyRepoIncluded({ id: 1, app_id: 12345, repository_selection: "all" }, "alice/bob");
if (!r1.ok || r1.reason !== "all") process.exit(1);
// 不正な installation → ng
const r2 = v.verifyRepoIncluded(null, "alice/bob");
if (r2.ok || r2.reason !== "invalid_installation") process.exit(1);
const r3 = v.verifyRepoIncluded({ id: 1, app_id: 12345, repository_selection: "unknown" }, "alice/bob");
if (r3.ok || r3.reason !== "verify_api_failed") process.exit(1);
// selected + installation.id が非整数 → invalid_installation
const r4 = v.verifyRepoIncluded({ id: "abc", app_id: 12345, repository_selection: "selected" }, "alice/bob");
if (r4.ok || r4.reason !== "invalid_installation") process.exit(1);
'; then
  pass "verifyRepoIncluded が all / 不正入力 / unknown を正しく判定（CISO 修正必須 1）"
else
  fail "verifyRepoIncluded の挙動が想定と異なる"
fi

# verify.js: verifyAppInstallation が appId 非整数を TypeError で拒否（CISO 入力検証）
if node -e '
const v = require("./cli/verify");
for (const bad of ["abc", null, undefined, 12.5, NaN, "", true]) {
  try {
    v.verifyAppInstallation("alice/bob", bad);
    console.error("Should have thrown for:", bad);
    process.exit(1);
  } catch (e) {
    if (!(e instanceof TypeError)) { console.error("not TypeError for:", bad); process.exit(1); }
  }
}
'; then
  pass "verifyAppInstallation が appId 非整数（abc / null / 12.5 / NaN / true 等）を TypeError で拒否"
else
  fail "verifyAppInstallation の appId 型サニタイズが想定と異なる"
fi

# install.js: redactCredentials が printResult から分離されたことの間接検証
# （source 解析: redactCredentials 関数が定義されており、run() の return 直前に呼ばれること）
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/install.js", "utf8");
if (!/function redactCredentials\(credentials\)/.test(src)) {
  console.error("redactCredentials not defined as function");
  process.exit(1);
}
// run() 内で redactCredentials が呼ばれること
if (!/redactCredentials\(credentials\)/.test(src)) {
  console.error("redactCredentials not invoked");
  process.exit(1);
}
// printResult からも呼ばれていること
const printResult = src.match(/function printResult[\s\S]*?\n\}/);
if (!printResult || !/redactCredentials/.test(printResult[0])) {
  console.error("redactCredentials not called from printResult");
  process.exit(1);
}
'; then
  pass "install.js の redactCredentials が printResult から分離され run() でも呼ばれる"
else
  fail "install.js の redactCredentials 分離・呼び出しが不足"
fi

# install.js: skipPrintResult: true でも credentials が REDACT されること
if node -e '
process.env.NODE_NO_WARNINGS = "1";
const install = require("./cli/install");
install.run({
  argv: ["--owner", "alice", "--dry-run"],
  openBrowser: () => {},
  readOwner: async () => "alice",
  skipConsent: true,
  skipPrintResult: true,
}).then((result) => {
  // dry-run なので credentials は無いが、戻り値が壊れていないことを確認
  if (result.dryRun !== true) process.exit(1);
  if (result.appName !== "vibehawk-for-alice") process.exit(1);
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "install.run({ skipPrintResult: true }) が --dry-run で正しく完了する（後方互換）"
else
  fail "install.run({ skipPrintResult: true }) が想定と異なる挙動"
fi

# 後方互換: install.run を headless オプション無しで呼んでも既存挙動維持
if node -e '
process.env.NODE_NO_WARNINGS = "1";
const install = require("./cli/install");
install.run({
  argv: ["--owner", "alice", "--dry-run"],
  openBrowser: () => {},
  readOwner: async () => "alice",
}).then((result) => {
  if (result.dryRun !== true) process.exit(1);
  if (result.appName !== "vibehawk-for-alice") process.exit(1);
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "install.run() を headless オプション無しで呼んでも既存挙動を維持（逆回帰）"
else
  fail "install.run() の headless オプション無し呼び出しで挙動が変わった可能性"
fi

# 後方互換: oauth.setupToken の skipPrintInstructions 無し呼び出し
if node -e '
const oauth = require("./cli/oauth");
oauth.setupToken({
  argv: ["--repo", "alice/bob"],
  rlFactory: () => ({
    question: (q, cb) => {
      if (q.includes("貼り付けて")) cb("ABCDEFG_HIJKLMN-1234567890.+/=ABCDEFG");
      else cb("");
    },
    close: () => {},
  }),
  clipboard: () => ({ success: true }),
  consent: async () => false,
}).then((result) => {
  if (result.repo !== "alice/bob") process.exit(1);
  if (result.settingsUrl !== "https://github.com/alice/bob/settings/secrets/actions/new") process.exit(1);
  // skipPrintInstructions 無しなら token を return しない（既存挙動）
  if (typeof result.token !== "undefined") { console.error("token should be undefined when skipPrintInstructions is omitted"); process.exit(1); }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "oauth.setupToken() を skipPrintInstructions 無しで呼ぶと token は return されない（後方互換）"
else
  fail "oauth.setupToken() の後方互換挙動が想定と異なる"
fi

# oauth.setupToken の skipPrintInstructions: true で token が return される
if node -e '
const oauth = require("./cli/oauth");
oauth.setupToken({
  argv: ["--repo", "alice/bob"],
  rlFactory: () => ({
    question: (q, cb) => {
      if (q.includes("貼り付けて")) cb("ABCDEFG_HIJKLMN-1234567890.+/=ABCDEFG");
      else cb("");
    },
    close: () => {},
  }),
  clipboard: () => ({ success: true }),
  consent: async () => true,
  skipPrintInstructions: true,
}).then((result) => {
  if (result.token !== "ABCDEFG_HIJKLMN-1234567890.+/=ABCDEFG") { console.error("token mismatch"); process.exit(1); }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "oauth.setupToken({ skipPrintInstructions: true }) で token が return される"
else
  fail "oauth.setupToken の skipPrintInstructions: true 経路が想定と異なる"
fi

# setup.js: parseDryRun が --dry-run を検出
if node -e '
const setup = require("./cli/setup");
if (setup.parseDryRun(["--dry-run"]) !== true) process.exit(1);
if (setup.parseDryRun([]) !== false) process.exit(1);
'; then
  pass "setup.parseDryRun が --dry-run を検出"
else
  fail "setup.parseDryRun の挙動が想定と異なる"
fi

# setup.js: buildSteps が STEPS.length === 7 を返す（Issue #249 で app-logo ステップ追加）
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
if (!Array.isArray(steps)) process.exit(1);
if (steps.length !== 7) { console.error("expected 7 steps, got:", steps.length); process.exit(1); }
// secret-token ステップが isSensitive: true
const tokenStep = steps.find((s) => s.id === "secret-token");
if (!tokenStep || tokenStep.isSensitive !== true) { console.error("secret-token must have isSensitive: true (CISO Critical)"); process.exit(1); }
// secret-app-id / app-install / app-logo は isSensitive: false
for (const id of ["app-install", "secret-app-id", "app-logo"]) {
  const s = steps.find((x) => x.id === id);
  if (!s || s.isSensitive !== false) { console.error(id, "must have isSensitive: false"); process.exit(1); }
}
'; then
  pass "buildSteps が 7 ステップを返し secret-token に isSensitive: true が付与されている（CISO Critical）"
else
  fail "buildSteps の構造が想定と異なる"
fi

# setup.js: buildState / clearState がメモリ参照を null 化
if node -e '
const setup = require("./cli/setup");
const s = setup.buildState();
s.credentials = { id: 12345, pem: "secret" };
s.appIdString = "12345";
s.oauthToken = "fake-token";
setup.clearState(s);
if (s.credentials !== null) process.exit(1);
if (s.appIdString !== null) process.exit(1);
if (s.oauthToken !== null) process.exit(1);
'; then
  pass "clearState が credentials / appIdString / oauthToken を null 化（SIGINT 時のクリーンアップ）"
else
  fail "clearState の挙動が想定と異なる"
fi

# setup.js: @clack/prompts が require できる（依存追加が完了）
if node -e '
try { require("@clack/prompts"); process.exit(0); } catch (e) { console.error(e.message); process.exit(1); }
'; then
  pass "@clack/prompts が require できる"
else
  fail "@clack/prompts が require できない（依存未追加？）"
fi

# package.json に @clack/prompts dependency があり、devDependencies ではない
if node -e '
const pkg = require("./package.json");
if (!pkg.dependencies || !pkg.dependencies["@clack/prompts"]) process.exit(1);
if (pkg.devDependencies && pkg.devDependencies["@clack/prompts"]) process.exit(1);
'; then
  pass "@clack/prompts が dependencies（devDependencies ではない）に追加されている"
else
  fail "@clack/prompts の package.json 配置が想定と異なる"
fi

# setup.js: --dry-run で spawnSync / install.run の実 GitHub 通信が走らないこと
# （checkGhAuth は dry-run でもスキップされる、@clack/prompts はモック化）
if node -e '
process.env.NODE_NO_WARNINGS = "1";
// @clack/prompts を最小限モックして TTY 要求を回避
require.cache[require.resolve("@clack/prompts")] = {
  exports: {
    intro: () => {},
    outro: () => {},
    text: async () => "mock",
    select: async () => "retry",
    note: () => {},
    spinner: () => ({ start: () => {}, stop: () => {} }),
    cancel: () => {},
    isCancel: () => false,
    group: async () => {},
  },
};
const setup = require("./cli/setup");

// spawnSync を差し替え（呼ばれたら fail）
const cp = require("child_process");
const origSpawnSync = cp.spawnSync;
let spawnSyncCalled = false;
cp.spawnSync = function() { spawnSyncCalled = true; return { status: 1, stdout: "", stderr: "" }; };

// fetch を差し替え（呼ばれたら fail）
let fetchCalled = false;
global.fetch = () => { fetchCalled = true; return Promise.reject(new Error("should not be called")); };

setup.run({ argv: ["--owner", "alice", "--repo", "alice/bob", "--dry-run"] }).then((result) => {
  cp.spawnSync = origSpawnSync;
  if (spawnSyncCalled) { console.error("spawnSync called in dry-run"); process.exit(1); }
  if (fetchCalled) { console.error("fetch called in dry-run"); process.exit(1); }
  if (result.dryRun !== true) { console.error("result.dryRun should be true"); process.exit(1); }
  if (result.owner !== "alice") process.exit(1);
  if (result.repo !== "alice/bob") process.exit(1);
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "setup --dry-run で spawnSync / fetch が呼ばれない"
else
  fail "setup --dry-run で spawnSync / fetch が呼ばれる可能性"
fi

# CISO 修正必須 2: executeStep の run フェーズが for ループで MAX_RETRY 上限を持つ
# （無限再帰防止）
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/setup.js", "utf8");
const m = src.match(/async function executeStep[\s\S]*?\n\}/);
if (!m) { console.error("executeStep not found"); process.exit(1); }
const body = m[0];
// run フェーズで return executeStep(...) の再帰呼び出しがないこと
if (/return executeStep\(/.test(body)) { console.error("recursive executeStep call still exists"); process.exit(1); }
// run フェーズに for ループが存在し、MAX_RETRY を参照すること
if (!/for\s*\(\s*let\s+attempt\s*=\s*0\s*;\s*attempt\s*<\s*MAX_RETRY/.test(body)) { console.error("MAX_RETRY for-loop not found"); process.exit(1); }
'; then
  pass "executeStep の run フェーズが MAX_RETRY 上限の for ループに変換されている（CISO 修正必須 2、無限再帰防止）"
else
  fail "executeStep の run フェーズが再帰のまま（CISO 修正必須 2 未対応）"
fi

# CISO 修正必須 3: step.verify(state) が await されている
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/setup.js", "utf8");
// `v = step.verify(state);` ではなく `v = await step.verify(state);` であること
if (/v\s*=\s*step\.verify\(state\);/.test(src)) { console.error("step.verify() not awaited"); process.exit(1); }
if (!/v\s*=\s*await\s+step\.verify\(state\)/.test(src)) { console.error("await step.verify(state) not found"); process.exit(1); }
'; then
  pass "step.verify(state) が await されている（CISO 修正必須 3、将来非同期化対応）"
else
  fail "step.verify(state) が await されていない（CISO 修正必須 3 未対応）"
fi

# CLO 条件 4: docs/external-dependency-audit.md に @clack/prompts が含まれる
if grep -F "@clack/prompts" docs/external-dependency-audit.md > /dev/null; then
  pass "docs/external-dependency-audit.md に @clack/prompts エントリが追加されている（CLO 条件 2 + 4）"
else
  fail "docs/external-dependency-audit.md に @clack/prompts エントリがない"
fi

# Issue #103: GitHub App manifest hook_attributes.url 検証
# - 修正前は hook_attributes が { active: false } のみで、GitHub manifest validation が
#   "url wasn't supplied" で停止していた（Issue #56 dogfooding が発見）
# - hook_attributes.url を必須化しつつ、active: false で実送信を抑止
# - URL は RFC 2606 reserved TLD .invalid を採用し、active が将来 true に誤変更されても
#   名前解決段階で失敗することで外部到達を二重に防ぐ
echo "=== GitHub App manifest 構造検証 (Issue #103) ==="

manifest_json=$(node -e "console.log(JSON.stringify(require('./cli/manifest').buildManifest({port:12345, name:'vibehawk-for-test'})))")

# assert 1: hook_attributes.url が string 型かつ non-empty（GitHub manifest validation 通過の必須要件）
# bash 文字列化のみだと数値・bool などが空文字判定をすり抜けるため jq で型と長さを同時検証
hook_url=$(echo "$manifest_json" | jq -r '.hook_attributes.url // empty')
if echo "$manifest_json" | jq -e '.hook_attributes.url | type == "string" and length > 0' > /dev/null; then
  pass "hook_attributes.url が string 型かつ non-empty"
else
  fail "hook_attributes.url が string 型 / non-empty でない（GitHub manifest validation で url wasn't supplied エラーまたは型違反）"
fi

# assert 2: hook_attributes.active が false（webhook 実送信抑止の既存挙動保証）
hook_active=$(echo "$manifest_json" | jq -r '.hook_attributes.active')
if [[ "$hook_active" == "false" ]]; then
  pass "hook_attributes.active が false（webhook 実送信を抑止）"
else
  fail "hook_attributes.active が false でない (got: $hook_active)、webhook 実送信のリスク"
fi

# assert 3a: hook_attributes.url に vibehawk が含まれない（大文字小文字問わず）
# 個別ドメイン列挙よりパターンマッチが堅牢で将来の運営側ドメイン追加にも対応する
# specification.md「vibehawk 運営側のサーバーには一切通信しない」原則の機械化
if echo "$hook_url" | grep -qi 'vibehawk'; then
  fail "hook_attributes.url が vibehawk 運営側を示唆するドメインを参照 ($hook_url)、specification.md 違反"
else
  pass "hook_attributes.url が vibehawk 運営側を示唆しない（外部エンドポイント不使用、CISO/CPO 注記の機械化）"
fi

# assert 3b: hook_attributes.url が RFC 2606 reserved TLD .invalid を使用（外部到達防止の回帰検知）
# vibehawk 非包含だけでは別の実在ドメインへの変更を検出できないため、.invalid TLD 必須を併記する
# .invalid は RFC 2606 で名前解決不可と保証されており、active が将来 true に誤変更されても外部到達しない
if echo "$manifest_json" | jq -e '.hook_attributes.url | type == "string" and test("^https?://([A-Za-z0-9-]+\\.)*invalid(/|$)")' > /dev/null; then
  pass "hook_attributes.url が RFC 2606 reserved TLD .invalid を使用（外部到達防止の回帰検知）"
else
  fail "hook_attributes.url が .invalid 以外のドメインを使用（外部到達リスク、URL 選定根拠の崩壊）"
fi

# assert 4: トップレベル url フィールドが non-empty string（GitHub App ホームページ URL の regression 防止）
top_url=$(echo "$manifest_json" | jq -r '.url // empty')
if [[ -n "$top_url" ]]; then
  pass "トップレベル url フィールドが non-empty string"
else
  fail "トップレベル url フィールドが空または欠落（GitHub manifest validation エラー）"
fi

# Issue #110: setup ウィザード Step 2 (app-install) が `gh api /user/installations` を
# 呼ばず利用者の目視確認経路に切り替わったことを機械検証する。
# 背景: `/user/installations` は GitHub App user-to-server token 専用で利用者 PAT では 403。
# Issue #56 dogfooding で発覚し、本 Issue で目視確認経路に切替えた。
echo "=== Step 2 目視確認経路への切替検証 (Issue #110) ==="

# assert 1: app-install ステップの verify が { ok: true, reason: 'manual_confirmation' } を返す
# （= gh api 呼び出しを伴わない no-op）
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const appInstall = steps.find((s) => s.id === "app-install");
if (!appInstall) { console.error("app-install step not found"); process.exit(1); }
if (typeof appInstall.verify !== "function") { console.error("verify must be a function (manual confirmation no-op)"); process.exit(1); }
const r = appInstall.verify({ credentials: { id: 12345 }, appIdString: "12345" });
if (!r || r.ok !== true) { console.error("verify must return { ok: true } for manual confirmation, got:", r); process.exit(1); }
if (r.reason !== "manual_confirmation") { console.error("verify reason must be manual_confirmation, got:", r.reason); process.exit(1); }
'; then
  pass "app-install の verify が { ok: true, reason: 'manual_confirmation' } を返す（Issue #110: 目視確認経路）"
else
  fail "app-install の verify が目視確認経路（manual_confirmation）になっていない"
fi

# assert 2: app-install の verify 実行で spawnSync（= gh api 呼び出し）が発生しない
# （根本原因の機械保証: `/user/installations` が呼ばれなくなったこと）
if node -e '
const cp = require("child_process");
const origSpawnSync = cp.spawnSync;
let spawnSyncCalled = false;
cp.spawnSync = function() { spawnSyncCalled = true; return { status: 0, stdout: "{}", stderr: "" }; };
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const appInstall = steps.find((s) => s.id === "app-install");
const r = appInstall.verify({ credentials: { id: 12345 }, appIdString: "12345" });
cp.spawnSync = origSpawnSync;
if (spawnSyncCalled) { console.error("spawnSync was called during app-install.verify (gh api still invoked)"); process.exit(1); }
if (!r || r.ok !== true) { console.error("verify must return ok:true"); process.exit(1); }
'; then
  pass "app-install の verify が spawnSync を呼ばない（gh api /user/installations 経路が完全に消えた）"
else
  fail "app-install の verify が依然として spawnSync を呼ぶ（403 問題が再発する可能性）"
fi

# assert 3: app-install ステップに getInstructions が存在し、利用者誘導文言を含む
# （目視確認経路の UX 担保: 自動検証できない理由 + 警告を必ず表示する）
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const appInstall = steps.find((s) => s.id === "app-install");
if (typeof appInstall.getInstructions !== "function") { console.error("getInstructions must be a function"); process.exit(1); }
const instr = appInstall.getInstructions({ credentials: { id: 12345 }, appIdString: "12345" });
if (typeof instr !== "string" || instr.length === 0) { console.error("getInstructions must return non-empty string"); process.exit(1); }
if (!/目視/.test(instr)) { console.error("instructions must mention 目視確認 rationale"); process.exit(1); }
if (!/自動検証/.test(instr)) { console.error("instructions must mention 自動検証 limitation"); process.exit(1); }
if (!/インストール/.test(instr)) { console.error("instructions must mention インストール guidance"); process.exit(1); }
'; then
  pass "app-install の getInstructions が利用者誘導文言（目視 / 自動検証 / インストール）を含む"
else
  fail "app-install の getInstructions が利用者誘導文言を欠く"
fi

# assert 4: app-install の getUrl が /installations/new を含む（既存 UX の回帰防止）
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const appInstall = steps.find((s) => s.id === "app-install");
const url = appInstall.getUrl({ credentials: { html_url: "https://github.com/apps/vibehawk-for-alice" } });
if (typeof url !== "string" || !url.includes("/installations/new")) {
  console.error("getUrl must include /installations/new, got:", url);
  process.exit(1);
}
'; then
  pass "app-install の getUrl が /installations/new を含む（既存 UX 回帰防止）"
else
  fail "app-install の getUrl が /installations/new を含まない"
fi

# Issue #112: secret-pem の getUrl が /settings/apps/<slug> を案内する
# （`/apps/<slug>` は公開ページで「Generate a private key」ボタンが存在しないため、
#  所有者専用の設定ページ `/settings/apps/<slug>` を案内する必要がある）
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const secretPem = steps.find((s) => s.id === "secret-pem");
if (typeof secretPem.getUrl !== "function") { console.error("secret-pem.getUrl must be a function"); process.exit(1); }
const url = secretPem.getUrl({ credentials: { slug: "vibehawk-for-alice", html_url: "https://github.com/apps/vibehawk-for-alice" } });
if (typeof url !== "string" || !url.includes("https://github.com/settings/apps/vibehawk-for-alice")) {
  console.error("getUrl must include /settings/apps/<slug>, got:", url);
  process.exit(1);
}
// PR #148 CodeRabbit Major 対応: 公開 URL 否定アサートを完全URL一致に強化（trailing space 依存だと回帰を取りこぼす）
if (url.includes("https://github.com/apps/vibehawk-for-alice")) {
  console.error("getUrl must NOT use public /apps/<slug> URL (no Generate a private key button there), got:", url);
  process.exit(1);
}
'; then
  pass "secret-pem の getUrl が /settings/apps/<slug> を案内する（Issue #112: Private key 取得画面に直接遷移）"
else
  fail "secret-pem の getUrl が /settings/apps/<slug> を案内しない（Issue #112: Private key 生成ボタンが存在しない URL を案内している）"
fi

# assert 5: cli/verify.js の verifyAppInstallation export が維持されている
# （将来 App JWT 経由で検証復活させる際の拡張余地、計画段階の設計判断）
if node -e '
const verify = require("./cli/verify");
if (typeof verify.verifyAppInstallation !== "function") {
  console.error("verifyAppInstallation export must be retained for future re-use");
  process.exit(1);
}
'; then
  pass "cli/verify.js の verifyAppInstallation export が維持されている（将来再利用余地）"
else
  fail "cli/verify.js の verifyAppInstallation export が失われた"
fi

# assert 6: cli/setup.js の実コード（コメント除外）が /user/installations 文字列を参照しない
# （根本原因の機械保証: setup.js のランタイムから `/user/installations` 呼び出しが完全に消えた）
# 行頭が // または * のコメント行を除外したうえで grep（既存の CISO 検証パターンと同方式）
if grep -vE '^\s*(//|\*)' cli/setup.js | grep -F '/user/installations' > /dev/null; then
  fail "cli/setup.js の実コードが /user/installations を参照（Issue #110 の根本原因が残存）"
else
  pass "cli/setup.js の実コードが /user/installations を参照しない（Issue #110 根本原因の機械保証）"
fi

# Issue #249: app-logo ステップ（bot アイコン用デフォルトロゴ同梱 + アップロード誘導）
echo "=== app-logo ステップ検証 (Issue #249) ==="

# assert 1: app-logo が app-create の直後に挿入されている（App 作成ステップ直後の案内表示）
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const createIdx = steps.findIndex((s) => s.id === "app-create");
const logoIdx = steps.findIndex((s) => s.id === "app-logo");
if (logoIdx === -1) { console.error("app-logo step not found"); process.exit(1); }
if (logoIdx !== createIdx + 1) { console.error("app-logo must be right after app-create, createIdx:", createIdx, "logoIdx:", logoIdx); process.exit(1); }
'; then
  pass "app-logo ステップが app-create の直後に挿入されている（Issue #249: App 作成ステップ直後の案内）"
else
  fail "app-logo ステップが app-create の直後に挿入されていない"
fi

# assert 2: app-logo の getUrl が /settings/apps/<slug>（Display information）を案内する
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const logo = steps.find((s) => s.id === "app-logo");
if (typeof logo.getUrl !== "function") { console.error("app-logo.getUrl must be a function"); process.exit(1); }
const url = logo.getUrl({ credentials: { slug: "vibehawk-for-alice" } });
if (typeof url !== "string" || !url.includes("https://github.com/settings/apps/vibehawk-for-alice")) {
  console.error("getUrl must include /settings/apps/<slug>, got:", url);
  process.exit(1);
}
const fallback = logo.getUrl({ credentials: {} });
if (fallback.includes("undefined")) { console.error("getUrl must not emit undefined when slug missing, got:", fallback); process.exit(1); }
'; then
  pass "app-logo の getUrl が /settings/apps/<slug> を案内し slug 欠落時も undefined を混入しない"
else
  fail "app-logo の getUrl が /settings/apps/<slug> を案内しない"
fi

# assert 3: app-logo の getInstructions が同梱画像の場所（assets/vibehawk-logo.png）を明示する
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const logo = steps.find((s) => s.id === "app-logo");
if (typeof logo.getInstructions !== "function") { console.error("app-logo.getInstructions must be a function"); process.exit(1); }
const instr = logo.getInstructions({ credentials: { slug: "vibehawk-for-alice" } });
if (typeof instr !== "string" || instr.length === 0) { console.error("getInstructions must return non-empty string"); process.exit(1); }
if (!instr.includes("assets") || !instr.includes("vibehawk-logo.png")) {
  console.error("getInstructions must include bundled image path (assets/vibehawk-logo.png), got:", instr);
  process.exit(1);
}
if (!/ドラッグ|アップロード/.test(instr)) { console.error("getInstructions must guide upload, got:", instr); process.exit(1); }
'; then
  pass "app-logo の getInstructions が同梱画像の場所（assets/vibehawk-logo.png）とアップロード手順を明示する"
else
  fail "app-logo の getInstructions が同梱画像の場所 / アップロード手順を欠く"
fi

# assert 4: app-logo の verify が目視確認経路（manual_confirmation）で credential 経路に触れない（挙動不変）
if node -e '
const setup = require("./cli/setup");
const cp = require("child_process");
let spawnSyncCalled = false;
const orig = cp.spawnSync;
cp.spawnSync = function() { spawnSyncCalled = true; return { status: 0, stdout: "{}", stderr: "" }; };
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const logo = steps.find((s) => s.id === "app-logo");
const v = logo.verify({ credentials: { slug: "vibehawk-for-alice" } });
cp.spawnSync = orig;
if (!v || v.ok !== true || v.reason !== "manual_confirmation") { console.error("verify must return manual_confirmation, got:", JSON.stringify(v)); process.exit(1); }
if (spawnSyncCalled) { console.error("app-logo.verify must NOT call spawnSync (credential/外部通信なし)"); process.exit(1); }
if (typeof logo.getValue === "function") { console.error("app-logo must NOT define getValue (credential 経路に触れない)"); process.exit(1); }
'; then
  pass "app-logo の verify が manual_confirmation で spawnSync / getValue を持たない（挙動不変: credential 経路不変）"
else
  fail "app-logo の verify が credential 経路に触れている（挙動不変違反）"
fi

# assert 5: 同梱ロゴ画像が配布物に存在し PNG / 1MB 未満（完了条件）
if [[ -f assets/vibehawk-logo.png ]]; then
  logo_size=$(wc -c < assets/vibehawk-logo.png)
  logo_head=$(head -c 8 assets/vibehawk-logo.png | od -An -tx1 | tr -d ' \n')
  if [[ "$logo_head" == "89504e470d0a1a0a" && "$logo_size" -lt 1048576 ]]; then
    pass "assets/vibehawk-logo.png が PNG シグネチャを持ち 1MB 未満（${logo_size} bytes）"
  else
    fail "assets/vibehawk-logo.png が PNG でない or 1MB 以上（head: ${logo_head}, size: ${logo_size}）"
  fi
else
  fail "assets/vibehawk-logo.png が存在しない（同梱ロゴ未配置）"
fi

# assert 5b: 同梱ロゴが正方形かつ 512px 以上（Issue #325: high-DPI 向け高解像度化）
# PNG の IHDR から幅/高さを読む（node 経由でクロスプラットフォーム）
if node -e '
const fs = require("fs");
const b = fs.readFileSync("assets/vibehawk-logo.png");
const w = b.readUInt32BE(16), h = b.readUInt32BE(20);
if (w !== h) { console.error("logo must be square, got:", w, "x", h); process.exit(1); }
if (w < 512) { console.error("logo must be >= 512px, got:", w); process.exit(1); }
'; then
  pass "assets/vibehawk-logo.png が正方形かつ 512px 以上（high-DPI 向け、Issue #325）"
else
  fail "assets/vibehawk-logo.png が正方形でない or 512px 未満（Issue #325 完了条件違反）"
fi

# assert 6: package.json の files に assets/ が含まれ npm 配布物に同梱される（完了条件）
if node -e '
const pkg = require("./package.json");
if (!Array.isArray(pkg.files) || !pkg.files.includes("assets/")) { console.error("package.json files must include assets/, got:", JSON.stringify(pkg.files)); process.exit(1); }
'; then
  pass "package.json の files に assets/ が含まれる（npm 配布物にロゴが同梱される）"
else
  fail "package.json の files に assets/ が含まれない（ロゴが配布物に同梱されない）"
fi

# Issue #91 dogfooding 計測機能の機械検証
# 完了条件「dogfooding で 5 分以内に完走することを確認」を客観的に判定可能にする実装が入っていることを検証
echo "=== dogfooding 計測機能検証 (Issue #91) ==="

# assert 1: cli/setup.js に Date.now() 呼び出しが含まれる（所要時間計測の存在）
if grep -F 'Date.now()' cli/setup.js > /dev/null; then
  pass "cli/setup.js に Date.now() 呼び出しが存在する（所要時間計測の起点）"
else
  fail "cli/setup.js に Date.now() 呼び出しがない（所要時間計測されない）"
fi

# assert 2: cli/setup.js に durationMs フィールド書き込みが存在する（summary への所要時間記録）
if grep -F 'durationMs' cli/setup.js > /dev/null; then
  pass "cli/setup.js に durationMs フィールドが存在する（summary に所要時間が記録される）"
else
  fail "cli/setup.js に durationMs フィールドがない（summary に所要時間が記録されない）"
fi

# assert 3: 5 分閾値定数 DOGFOODING_TARGET_MS が 300_000 ms（5 * 60 * 1000）として定義される
# set -e 下でコマンド置換 `$(...)` の失敗は即終了するため、明示的に if で捕捉し fail() 集計に載せる
if target_ms=$(node -e 'console.log(require("./cli/setup").DOGFOODING_TARGET_MS)' 2>&1); then
  if [[ "$target_ms" == "300000" ]]; then
    pass "DOGFOODING_TARGET_MS が 300000 ms（Issue #91 完了条件: 5 分以内）"
  else
    fail "DOGFOODING_TARGET_MS が 300000 ms ではない (got: $target_ms)、完了条件と整合しない"
  fi
else
  fail "DOGFOODING_TARGET_MS の取得に失敗した (output: $target_ms)"
fi

# assert 4: formatDuration が境界値で破綻しない（NaN / 負数 / 非数値 → 'n/a' フォールバック）
# - 59.95s 以上の境界値（toFixed(1) で "60.0" に丸まる）は "1m0s" に繰り上げる
# - 119999ms（Math.round で remainSeconds=60 となるケース）は "2m0s" に繰り上げる
if node -e '
const { formatDuration } = require("./cli/setup");
const checks = [
  [formatDuration(500), "500ms"],
  [formatDuration(5000), "5.0s"],
  [formatDuration(65000), "1m5s"],
  [formatDuration(300000), "5m0s"],
  [formatDuration(NaN), "n/a"],
  [formatDuration(-1), "n/a"],
  [formatDuration("abc"), "n/a"],
  [formatDuration(59999), "1m0s"],
  [formatDuration(59500), "59.5s"],
  [formatDuration(119999), "2m0s"],
];
for (const [actual, expected] of checks) {
  if (actual !== expected) {
    console.error(`formatDuration mismatch: actual=${actual} expected=${expected}`);
    process.exit(1);
  }
}
'; then
  pass "formatDuration が境界値（NaN / 負数 / 非数値 / 60s 境界）で破綻しない"
else
  fail "formatDuration が境界値で想定通りの文字列を返さない"
fi

# assert 5: dry-run で所要時間表示が stdout に出る（E2E 確認）
# set -e 下でコマンド置換 `$(...)` の失敗は即終了するため、明示的に if で捕捉し fail() 集計に載せる
# dry_run_ok フラグで後続 grep をスキップし、本来の失敗原因（dry-run 実行自体の失敗）を冗長 fail に埋もれさせない
dry_run_ok=true
if dry_run_output=$(node cli/index.js setup --dry-run --owner test --repo test/test 2>&1); then
  :
else
  fail "dry-run 実行自体が失敗した（後続の grep 検証はスキップする）"
  dry_run_output=""
  dry_run_ok=false
fi

if [[ "$dry_run_ok" == "true" ]] && echo "$dry_run_output" | grep -F 'dogfooding 計測' > /dev/null; then
  pass "dry-run 実行で「dogfooding 計測」見出しが表示される"
elif [[ "$dry_run_ok" == "false" ]]; then
  :
else
  fail "dry-run 実行で「dogfooding 計測」見出しが表示されない"
fi

if [[ "$dry_run_ok" == "true" ]] && echo "$dry_run_output" | grep -F '5m0s' > /dev/null; then
  pass "dry-run 実行で「5m0s」（5 分目標）が表示される"
elif [[ "$dry_run_ok" == "false" ]]; then
  :
else
  fail "dry-run 実行で「5m0s」（5 分目標）が表示されない"
fi

# assert 6: run() 戻り値に durationMs が含まれる（プログラマブル利用の保証）
if node -e '
const setup = require("./cli/setup");
(async () => {
  const result = await setup.run({ argv: ["--dry-run", "--owner", "test", "--repo", "test/test"] });
  if (typeof result.durationMs !== "number") {
    console.error("durationMs is not a number:", result);
    process.exit(1);
  }
})();
' > /dev/null 2>&1; then
  pass "run() の戻り値に durationMs（number）が含まれる"
else
  fail "run() の戻り値に durationMs（number）が含まれない"
fi

# assert 7: run() 戻り値に meetsDogfoodingTarget が含まれる（dry-run でも API 形状が一致）
# dry-run はほぼ即時完了するため totalElapsedMs <= DOGFOODING_TARGET_MS が成立し true になる
if node -e '
const setup = require("./cli/setup");
(async () => {
  const result = await setup.run({ argv: ["--dry-run", "--owner", "test", "--repo", "test/test"] });
  if (typeof result.meetsDogfoodingTarget !== "boolean") {
    console.error("meetsDogfoodingTarget is not a boolean:", result);
    process.exit(1);
  }
  if (result.meetsDogfoodingTarget !== true) {
    console.error("meetsDogfoodingTarget is not true for dry-run:", result);
    process.exit(1);
  }
})();
' > /dev/null 2>&1; then
  pass "run() の戻り値に meetsDogfoodingTarget（boolean, dry-run で true）が含まれる"
else
  fail "run() の戻り値に meetsDogfoodingTarget が含まれない、または期待値（true）と異なる"
fi

# Issue #109: setup ウィザード Step 5 で claude setup-token 実行ガイダンスを sandbox 環境向けに拡充
# 案内文の実体は cli/oauth.js の promptToken（および補足は cli/setup.js）。
# 必要キーワードがガイダンス内に含まれているかを grep で機械検証する。
echo "--- Issue #109: Step 5 ガイダンス拡充の検証 ---"

# キーワード一覧（Issue #109 完了条件にマップ）
# - 別ターミナル明示
# - alias バイパス（\claude または command claude）
# - HOME 外 cd 例（cd /tmp）
# - 再帰起動注意（Claude Code 内 !claude setup-token は再帰）
# - 代替経路（Anthropic Console / ANTHROPIC_API_KEY）
declare -a OAUTH_KEYWORDS=(
  "別ターミナル"
  "\\\\claude"
  "cd /tmp"
  "再帰"
  "console.anthropic.com"
  "ANTHROPIC_API_KEY"
)

for kw in "${OAUTH_KEYWORDS[@]}"; do
  if grep -F -- "$kw" cli/oauth.js > /dev/null; then
    pass "cli/oauth.js に Step 5 ガイダンス キーワード '$kw' が含まれる"
  else
    fail "cli/oauth.js に Step 5 ガイダンス キーワード '$kw' が含まれていない"
  fi
done

# cli/setup.js の showClipboardFallback 内の再取得案内文も alias 回避を反映している
if grep -F -- "\\\\claude setup-token" cli/setup.js > /dev/null; then
  pass "cli/setup.js の再取得案内に alias 回避形式（\\claude setup-token）が含まれる"
else
  fail "cli/setup.js の再取得案内に alias 回避形式（\\claude setup-token）が含まれていない"
fi

# Issue #111: setup ウィザードが OAuth token 取得失敗で異常終了せず Step 6 まで継続することの機械検証
#
# 根本原因: cli/setup.js executeStep の run フェーズ try-catch が再 throw していたため、
# Step 5 (secret-token) で oauth.setupToken → promptToken → validateToken が空 token で reject
# すると、外側 run() の catch で「予期しないエラー」表示 → process.exit(1) でウィザード全体が
# 異常終了し Step 6 (workflow PR 作成) に到達できなかった。
#
# 修正方針: catch 内で CancelError のみ再 throw、それ以外は { ok: false, hint: e.message } 化して
# 既存の retry/skip/cancel フローに合流させる。
echo "=== Issue #111: OAuth token 取得失敗時の Step 6 継続検証 ==="

# assert 1: 静的解析 — executeStep の run フェーズ try-catch が CancelError 以外を再 throw しない
# （CancelError のみ再 throw、それ以外は { ok: false, hint: ... } 化）
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/setup.js", "utf8");
const m = src.match(/async function executeStep[\s\S]*?\n\}/);
if (!m) { console.error("executeStep not found"); process.exit(1); }
const body = m[0];
// run フェーズ try-catch ブロックを抽出
const runTryCatch = body.match(/r\s*=\s*await\s+step\.run\(state\);\s*\}\s*catch\s*\(e\)\s*\{[\s\S]*?\}\s*if\s*\(r\.ok\)/);
if (!runTryCatch) { console.error("run try-catch block not found"); process.exit(1); }
// 行頭が // で始まる行コメントを除外してから throw e をカウント（コメント文中の説明文を誤検出しない）
const catchBodyNoComments = runTryCatch[0].split("\n").filter((line) => !/^\s*\/\//.test(line)).join("\n");
// CancelError 分岐があり、その分岐内でのみ throw e する形であること
if (!/if\s*\(\s*e\s+instanceof\s+CancelError\s*\)/.test(catchBodyNoComments)) {
  console.error("CancelError instanceof branch not found in run catch");
  process.exit(1);
}
// catch ブロック内に通常の throw e（CancelError 分岐外）が無いこと
// → CancelError 分岐の throw e 以外に throw e があるか確認
const throwCount = (catchBodyNoComments.match(/throw\s+e\b/g) || []).length;
if (throwCount !== 1) {
  console.error("expected exactly 1 throw e (inside CancelError branch), got:", throwCount);
  console.error("catchBodyNoComments:\n" + catchBodyNoComments);
  process.exit(1);
}
// catch ブロック内で r = { ok: false, hint: ... } 化していること
if (!/r\s*=\s*\{\s*ok:\s*false[^}]*hint/.test(catchBodyNoComments)) {
  console.error("catch block must set r = { ok: false, hint: ... }");
  process.exit(1);
}
'; then
  pass "executeStep run フェーズ try-catch: CancelError のみ再 throw、それ以外は { ok: false, hint } 化（Issue #111 根本修正）"
else
  fail "executeStep run フェーズ try-catch が Issue #111 修正方針と異なる（CancelError 以外を再 throw する可能性）"
fi

# assert 2: setup.run() が Step 5 で oauth.setupToken throw 時に process.exit(1) せず完走することの動的検証
# - @clack/prompts をモック化（select は 'skip' を返す、text は空文字を返す）
# - child_process.spawnSync をモック化（gh コマンドを成功偽装）
# - cli/oauth を require.cache 差し替えで setupToken が throw する形に置き換え
# - cli/install を require.cache 差し替えで run / createWorkflowPr を成功偽装
# - cli/verify を require.cache 差し替えで全 verify を { ok: true } 返却に偽装
# - setup.run を呼び、process.exit(1) ではなく summary が返ることを確認
if node -e '
process.env.NODE_NO_WARNINGS = "1";

// @clack/prompts モック: select は skip 固定、text は空文字、spinner は no-op
require.cache[require.resolve("@clack/prompts")] = {
  exports: {
    intro: () => {},
    outro: () => {},
    text: async () => "",
    select: async () => "skip",
    note: () => {},
    spinner: () => ({ start: () => {}, stop: () => {} }),
    cancel: () => {},
    isCancel: () => false,
    group: async () => {},
  },
};

// child_process.spawnSync モック: gh コマンド全てを success 偽装（checkGhAuth 通過用）
const cp = require("child_process");
const origSpawnSync = cp.spawnSync;
cp.spawnSync = function() { return { status: 0, stdout: "{}", stderr: "" }; };

// cli/install を success 偽装（app-create / workflow ステップ通過用）
require.cache[require.resolve("./cli/install")] = {
  exports: {
    run: async () => ({ id: 12345, name: "vibehawk-for-test", html_url: "https://github.com/apps/vibehawk-for-test" }),
    createWorkflowPr: async () => ({ url: "https://github.com/test/test/pull/1" }),
  },
};

// cli/verify を success 偽装（各検証ステップ通過用）
require.cache[require.resolve("./cli/verify")] = {
  exports: {
    verifySecret: () => ({ ok: true, reason: "found", hint: "" }),
    verifyAppInstallation: () => ({ ok: true, reason: "installed_via_user", hint: "" }),
    verifyWorkflow: () => ({ ok: true, reason: "found", hint: "" }),
  },
};

// cli/oauth を setupToken が throw する形にモック（Issue #111 の根本ケース再現）
// copyToClipboard も必須（setup.js が require 時に参照）
require.cache[require.resolve("./cli/oauth")] = {
  exports: {
    setupToken: async () => { throw new Error("vibehawk: OAuth token が空です"); },
    copyToClipboard: () => ({ success: true }),
    parseRepoArg: () => null,
  },
};

// process.exit を捕捉して呼ばれたら fail
const origExit = process.exit;
let exitCode = null;
process.exit = (code) => { exitCode = code; throw new Error("process.exit(" + code + ") called"); };

const setup = require("./cli/setup");
setup.run({ argv: ["--owner", "test", "--repo", "test/test"] }).then((result) => {
  process.exit = origExit;
  cp.spawnSync = origSpawnSync;
  if (exitCode !== null) {
    console.error("process.exit was called with:", exitCode);
    process.exit(1);
  }
  // summary が返り、secret-token が skipped 記録されていることを確認
  if (!result || !Array.isArray(result.summary)) {
    console.error("result.summary is not an array");
    process.exit(1);
  }
  const tokenSummary = result.summary.find((s) => s.id === "secret-token");
  if (!tokenSummary || tokenSummary.status !== "skipped") {
    console.error("secret-token must be skipped, got:", tokenSummary);
    process.exit(1);
  }
  // hint に「OAuth token が空」由来のメッセージが入っていること（e.message が伝搬している）
  if (!tokenSummary.hint || !/OAuth token/.test(tokenSummary.hint)) {
    console.error("secret-token.hint must contain OAuth token error message, got:", tokenSummary.hint);
    process.exit(1);
  }
  // workflow ステップが summary に含まれている（= Step 6 まで到達した）
  const workflowSummary = result.summary.find((s) => s.id === "workflow");
  if (!workflowSummary) {
    console.error("workflow step must be reached (Step 6 to be executed)");
    process.exit(1);
  }
  process.exit(0);
}).catch((e) => {
  process.exit = origExit;
  cp.spawnSync = origSpawnSync;
  console.error("setup.run threw:", e.message);
  process.exit(1);
});
' > /dev/null 2>&1; then
  pass "setup.run が Step 5 OAuth token throw 時に process.exit(1) せず、Step 6 まで完走し summary に skipped 記録される（Issue #111 動的検証）"
else
  fail "setup.run が Step 5 OAuth token throw 時に異常終了するか Step 6 に到達しない（Issue #111 動的検証失敗）"
fi

# assert 3: 完走サマリ表示文言（未登録 secrets / Secrets UI URL / 次のアクション）が setup.js に含まれる
if grep -F '未登録 secrets' cli/setup.js > /dev/null; then
  pass "cli/setup.js に「未登録 secrets」見出しが含まれる（Phase 2 サマリ拡張）"
else
  fail "cli/setup.js に「未登録 secrets」見出しが含まれない（Phase 2 サマリ拡張未実装）"
fi

if grep -F 'settings/secrets/actions' cli/setup.js > /dev/null; then
  pass "cli/setup.js に GitHub Secrets UI URL（settings/secrets/actions）が含まれる（Phase 2 サマリ拡張）"
else
  fail "cli/setup.js に GitHub Secrets UI URL が含まれない（Phase 2 サマリ拡張未実装）"
fi

if grep -F '次のアクション' cli/setup.js > /dev/null; then
  pass "cli/setup.js に「次のアクション」見出しが含まれる（Phase 2 サマリ拡張）"
else
  fail "cli/setup.js に「次のアクション」見出しが含まれない（Phase 2 サマリ拡張未実装）"
fi

# assert 4: SECRET_STEP_TO_NAME の 3 secret 名（VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY / CLAUDE_CODE_OAUTH_TOKEN）が
# サマリ生成ロジックに含まれること
for secret_name in "VIBEHAWK_APP_ID" "VIBEHAWK_PRIVATE_KEY" "CLAUDE_CODE_OAUTH_TOKEN"; do
  if grep -F "$secret_name" cli/setup.js > /dev/null; then
    pass "cli/setup.js に secret 名 '$secret_name' のサマリマッピングが含まれる"
  else
    fail "cli/setup.js に secret 名 '$secret_name' のサマリマッピングが含まれない"
  fi
done

# assert 5: CISO 観点 — oauth.js の validateToken が throw メッセージに token 値を埋め込まないこと
# （Issue #111 で e.message を stdout/hint に出すが、値漏洩しないことを機械保証）
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/oauth.js", "utf8");
const m = src.match(/function validateToken[\s\S]*?\n\}/);
if (!m) { console.error("validateToken not found"); process.exit(1); }
const body = m[0];
// throw new Error(...) の引数文字列に ${token} などの token 値補間がないこと
// テンプレートリテラル / 連結文字列内に token / answer 変数参照がないか確認
const throwMatches = body.match(/throw\s+new\s+Error\([^)]*\)/g) || [];
for (const throwStr of throwMatches) {
  if (/\$\{token\}|\$\{answer\}|"\s*\+\s*token|"\s*\+\s*answer|token\s*\+\s*"|answer\s*\+\s*"/.test(throwStr)) {
    console.error("validateToken throws with token value interpolated:", throwStr);
    process.exit(1);
  }
}
'; then
  pass "oauth.validateToken の throw メッセージに token 値が埋め込まれない（CISO 観点: Issue #111 値漏洩防止）"
else
  fail "oauth.validateToken の throw メッセージに token 値が埋め込まれる可能性（CISO Critical 違反）"
fi

# Issue #111 / PR #118 CodeRabbit 指摘: secret-token skip 時に state.oauthToken に空文字 sentinel を
# 残し、Step 6 (workflow) 開始時に「OAuth token が未登録です。手動登録が必要です」と案内する
echo "=== Issue #111 / PR #118: secret-token skip 時の sentinel + Step 6 未登録案内 検証 ==="

# assert 1: 静的解析 — executeStep の skip 分岐で state.oauthToken = '' を sentinel として残す
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/setup.js", "utf8");
const m = src.match(/async function executeStep[\s\S]*?\n\}/);
if (!m) { console.error("executeStep not found"); process.exit(1); }
const body = m[0];
// skip 分岐内で secret-token のとき state.oauthToken = "" or '"'"''"'"' をセットしていること
if (!/step\.id\s*===\s*['\''"]secret-token['\''"]\s*\)\s*\{\s*state\.oauthToken\s*=\s*['\''"]{2}/.test(body)) {
  console.error("skip branch must set state.oauthToken = '"'"''"'"' when step.id === '"'"'secret-token'"'"'");
  process.exit(1);
}
'; then
  pass "executeStep の skip 分岐で secret-token のとき state.oauthToken に空文字 sentinel をセットする（PR #118 CodeRabbit Major 対応）"
else
  fail "executeStep の skip 分岐で secret-token sentinel がセットされない（PR #118 CodeRabbit 指摘未修正）"
fi

# assert 2: 静的解析 — workflow ステップの run が state.oauthToken === '' を検知して案内する
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/setup.js", "utf8");
// workflow ステップの run 関数を抽出（id: "workflow" から次の閉じ括弧まで）
const m = src.match(/id:\s*['\''"]workflow['\''"][\s\S]*?run:\s*async[\s\S]*?createWorkflowPr/);
if (!m) { console.error("workflow step run not found"); process.exit(1); }
const body = m[0];
// state.oauthToken === "" を検知している
if (!/state\.oauthToken\s*===\s*['\''"]{2}/.test(body)) {
  console.error("workflow step run must check state.oauthToken === '"'"''"'"'");
  process.exit(1);
}
// 「OAuth token 未登録」または「CLAUDE_CODE_OAUTH_TOKEN が未登録」相当の案内文言を含むこと
if (!/CLAUDE_CODE_OAUTH_TOKEN.*未登録|OAuth token.*未登録/.test(body)) {
  console.error("workflow step run must show CLAUDE_CODE_OAUTH_TOKEN unregistered guidance");
  process.exit(1);
}
'; then
  pass "workflow ステップ run が state.oauthToken === '' を検知して「OAuth token が未登録」を案内する（PR #118 CodeRabbit Major 対応）"
else
  fail "workflow ステップ run で sentinel チェック + 未登録案内が実装されていない（PR #118 CodeRabbit 指摘未修正）"
fi

# assert 3: 動的検証 — secret-token skip 後、workflow ステップ実行時に state.oauthToken === '' であり
# 「OAuth token 未登録」案内が clack.note で出力されることを確認
if node -e '
process.env.NODE_NO_WARNINGS = "1";

// clack.note の呼び出しを記録するモック
const noteCallArgs = [];
require.cache[require.resolve("@clack/prompts")] = {
  exports: {
    intro: () => {},
    outro: () => {},
    text: async () => "",
    select: async () => "skip",
    note: (content, title) => { noteCallArgs.push({ content: String(content), title: String(title || "") }); },
    spinner: () => ({ start: () => {}, stop: () => {} }),
    cancel: () => {},
    isCancel: () => false,
    group: async () => {},
  },
};

const cp = require("child_process");
const origSpawnSync = cp.spawnSync;
cp.spawnSync = function() { return { status: 0, stdout: "{}", stderr: "" }; };

require.cache[require.resolve("./cli/install")] = {
  exports: {
    run: async () => ({ id: 12345, name: "vibehawk-for-test", html_url: "https://github.com/apps/vibehawk-for-test" }),
    createWorkflowPr: async () => ({ url: "https://github.com/test/test/pull/1" }),
  },
};

require.cache[require.resolve("./cli/verify")] = {
  exports: {
    verifySecret: () => ({ ok: true, reason: "found", hint: "" }),
    verifyAppInstallation: () => ({ ok: true, reason: "installed_via_user", hint: "" }),
    verifyWorkflow: () => ({ ok: true, reason: "found", hint: "" }),
  },
};

// cli/oauth: setupToken が throw（Step 5 skip ルート発火）
require.cache[require.resolve("./cli/oauth")] = {
  exports: {
    setupToken: async () => { throw new Error("vibehawk: OAuth token が空です"); },
    copyToClipboard: () => ({ success: true }),
    parseRepoArg: () => null,
  },
};

const origExit = process.exit;
let exitCode = null;
process.exit = (code) => { exitCode = code; throw new Error("process.exit(" + code + ") called"); };

const setup = require("./cli/setup");
setup.run({ argv: ["--owner", "test", "--repo", "test/test"] }).then((result) => {
  process.exit = origExit;
  cp.spawnSync = origSpawnSync;
  if (exitCode !== null) {
    console.error("process.exit was called with:", exitCode);
    process.exit(1);
  }
  // workflow ステップに到達したこと
  const workflowSummary = result.summary.find((s) => s.id === "workflow");
  if (!workflowSummary) {
    console.error("workflow step must be reached");
    process.exit(1);
  }
  // 「OAuth token 未登録」案内が clack.note で呼ばれていること
  const unregisteredNote = noteCallArgs.find((arg) =>
    /OAuth token.*未登録|CLAUDE_CODE_OAUTH_TOKEN.*未登録/.test(arg.content) ||
    /OAuth token.*未登録|CLAUDE_CODE_OAUTH_TOKEN.*未登録/.test(arg.title)
  );
  if (!unregisteredNote) {
    console.error("clack.note must be called with OAuth token unregistered guidance before workflow step");
    console.error("all note calls:", JSON.stringify(noteCallArgs.map((a) => a.title), null, 2));
    process.exit(1);
  }
  process.exit(0);
}).catch((e) => {
  process.exit = origExit;
  cp.spawnSync = origSpawnSync;
  console.error("setup.run threw:", e.message);
  process.exit(1);
});
' > /dev/null 2>&1; then
  pass "setup.run が secret-token skip 後の workflow ステップで「OAuth token 未登録」を clack.note で案内する（PR #118 CodeRabbit Major 動的検証）"
else
  fail "secret-token skip 後の workflow ステップで未登録案内が出力されない（PR #118 CodeRabbit Major 動的検証失敗）"
fi

# Issue #104: clack/prompts 枠線が日本語幅で崩れる問題のテスト
# East Asian Width 補正で .length === displayWidth になることを検証する
echo ""
echo "=== Issue #104: 枠線崩れ修正（East Asian Width 補正） ==="

if node -e '
const setup = require("./cli/setup");

// displayWidth: ASCII = 1 / Japanese = 2 / Surrogate emoji = 2 / VS-16 = 0
const cases = [
  ["", 0],
  ["abc", 3],
  ["あいう", 6],
  ["a日本", 5],
  ["🦅", 2],
  ["ℹ️", 2],
  ["owner: hirokimry", 16],
  // "CLI は secret を書き込みません" = 3+1+2+1+6+1+2+14 = 30
  ["CLI は secret を書き込みません", 30],
];
for (const [input, expected] of cases) {
  const actual = setup.displayWidth(input);
  if (actual !== expected) {
    console.error("displayWidth mismatch:", JSON.stringify(input), "expected:", expected, "actual:", actual);
    process.exit(1);
  }
}
process.exit(0);
' > /dev/null 2>&1; then
  pass "setup.displayWidth が East Asian Wide / surrogate emoji / VS-16 を正しく計算する（Issue #104）"
else
  fail "setup.displayWidth の計算が不正（Issue #104）"
fi

if node -e '
const setup = require("./cli/setup");

// normalizeNoteMessage: 全行で .length === max(displayWidth) となるよう揃える
const input = [
  "owner: hirokimry",
  "CLI は secret を書き込みません",
  "ℹ️ Anthropic への送信について:",
].join("\n");
const padded = setup.normalizeNoteMessage(input);
const lines = padded.split("\n");
const widths = lines.map(setup.displayWidth);
const target = Math.max(...widths);
for (const line of lines) {
  if (line.length !== target) {
    console.error("normalizeNoteMessage: .length !== target displayWidth", JSON.stringify(line), ".length:", line.length, "target:", target);
    process.exit(1);
  }
  if (setup.displayWidth(line) !== target) {
    console.error("normalizeNoteMessage: displayWidth !== target", JSON.stringify(line), "displayWidth:", setup.displayWidth(line), "target:", target);
    process.exit(1);
  }
}
process.exit(0);
' > /dev/null 2>&1; then
  pass "setup.normalizeNoteMessage が全行の .length と displayWidth を最大幅に揃える（Issue #104）"
else
  fail "normalizeNoteMessage の整合が不正（Issue #104）"
fi

if node -e '
const setup = require("./cli/setup");
// normalizeNoteTitle: 表示幅 === .length になる
const cases = ["セットアップ完了", "🦅 vibehawk セットアップ計画", "📋 clipboard"];
for (const t of cases) {
  const normalized = setup.normalizeNoteTitle(t);
  if (normalized.length !== setup.displayWidth(normalized)) {
    console.error("normalizeNoteTitle: .length !== displayWidth", JSON.stringify(t), "→", JSON.stringify(normalized));
    process.exit(1);
  }
}
process.exit(0);
' > /dev/null 2>&1; then
  pass "setup.normalizeNoteTitle が title の .length を displayWidth に揃える（Issue #104）"
else
  fail "normalizeNoteTitle の整合が不正（Issue #104）"
fi

if node -e '
process.env.NODE_NO_WARNINGS = "1";
const noteCallArgs = [];
require.cache[require.resolve("@clack/prompts")] = {
  exports: {
    intro: () => {},
    outro: () => {},
    text: async () => "mock",
    select: async () => "retry",
    note: (content, title) => { noteCallArgs.push({ content: String(content), title: String(title || "") }); },
    spinner: () => ({ start: () => {}, stop: () => {} }),
    cancel: () => {},
    isCancel: () => false,
    group: async () => {},
  },
};
const setup = require("./cli/setup");

setup.run({ argv: ["--owner", "alice", "--repo", "alice/bob", "--dry-run"] }).then(() => {
  if (noteCallArgs.length === 0) {
    console.error("expected at least 1 clack.note call");
    process.exit(1);
  }
  // 全 note 呼び出しで「全行の .length === max displayWidth」が成立
  for (const args of noteCallArgs) {
    const lines = args.content.split("\n");
    if (lines.length === 0) continue;
    const widths = lines.map(setup.displayWidth);
    const target = Math.max(...widths);
    for (const line of lines) {
      if (line.length !== target) {
        console.error("clack.note content line not normalized:", JSON.stringify(args.title), ".length:", line.length, "target:", target, "line:", JSON.stringify(line));
        process.exit(1);
      }
    }
    // title 側も .length === displayWidth
    if (args.title.length !== setup.displayWidth(args.title)) {
      console.error("clack.note title not normalized:", JSON.stringify(args.title), ".length:", args.title.length, "displayWidth:", setup.displayWidth(args.title));
      process.exit(1);
    }
  }
  process.exit(0);
}).catch((e) => {
  console.error("setup.run threw:", e.message);
  process.exit(1);
});
' > /dev/null 2>&1; then
  pass "setup.run が全 clack.note 呼び出しで content の全行と title を表示幅に揃える（Issue #104）"
else
  fail "setup.run の clack.note 呼び出しが表示幅補正を経由していない（Issue #104）"
fi

# Issue #104 完了条件: 実際の @clack/prompts に通したときに、出力ボックスの全行が
# 表示幅基準で等幅になっていること（= 右端の │ / ╮ / ╯ が同じ列に揃う）。
# clack の ANSI 着色を strip し、各行の表示幅が一致するかを assert する。
if node -e '
process.env.NODE_NO_WARNINGS = "1";
process.env.FORCE_COLOR = "0";
const setup = require("./cli/setup");

const chunks = [];
const orig = process.stdout.write.bind(process.stdout);
process.stdout.write = (chunk) => { chunks.push(typeof chunk === "string" ? chunk : chunk.toString()); return true; };

// 日本語 / 半角混在 / surrogate emoji / VS-16 emoji 混在の典型ケース
setup.note(
  [
    "owner: hirokimry",
    "repo:  alice/bob",
    "mode:  通常実行",
    "",
    "CLI は secret を書き込みません（Issue #72 / #74）。",
    "",
    "ℹ️ Anthropic への送信について:",
    "   本 CLI 自体は Anthropic に通信しません。",
  ].join("\n"),
  "🦅 vibehawk セットアップ計画"
);

process.stdout.write = orig;
const output = chunks.join("");
// ANSI escape を strip して列位置だけ見る
const ansi = /\[[0-9;]*m/g;
const lines = output.split("\n").map((l) => l.replace(ansi, ""));
// clack は note() の前後にバー単独行（"│" のみ）を出す。これは右端揃いの対象外なので除外。
const boxLines = lines.filter((l) => /[│╮╯]\s*$/.test(l) && setup.displayWidth(l.replace(/\s+$/, "")) > 2);
if (boxLines.length < 3) {
  console.error("expected at least 3 box lines (top + body + bottom), got:", boxLines.length);
  console.error("output:\n" + output);
  process.exit(1);
}
const widths = boxLines.map(setup.displayWidth);
const uniq = Array.from(new Set(widths));
if (uniq.length !== 1) {
  console.error("box right edge not aligned. widths:", widths);
  for (const l of boxLines) console.error(" w=" + setup.displayWidth(l) + " | " + l);
  process.exit(1);
}
process.exit(0);
' > /dev/null 2>&1; then
  pass "setup.note が日本語/emoji 混在文字列でも右端の │/╮/╯ を同じ表示列に揃える（Issue #104 完了条件）"
else
  fail "setup.note の右端枠線が揃わない（Issue #104 完了条件未達）"
fi

# Issue #134: setup ウィザード完了時に branch protection 誘導が出る
echo ""
echo "=== Issue #134: setup 完了後 branch protection 誘導 ==="

if grep -q "branch protection に \`vibehawk\` を required status check として登録" cli/setup.js; then
  pass "setup.js が branch protection 登録誘導の本文を含む（Issue #134）"
else
  fail "setup.js に branch protection 登録誘導がない（Issue #134）"
fi

if grep -q "settings/branches" cli/setup.js; then
  pass "setup.js が branch protection 設定の直リンク（settings/branches）を含む（Issue #134）"
else
  fail "setup.js に branch protection 設定 URL がない（Issue #134）"
fi

if grep -q "Require status checks to pass before merging" cli/setup.js; then
  pass "setup.js が branch protection の有効化キーワード（Require status checks）を案内する（Issue #134）"
else
  fail "setup.js に Require status checks 案内がない（Issue #134）"
fi

if grep -q "branchProtectionGated" cli/setup.js; then
  pass "setup.js が 3 secrets 完了 gate で branch protection 案内を出し分ける（Issue #134）"
else
  fail "setup.js に branchProtectionGated gating がない（Issue #134）"
fi

# Issue #356: 既存 App 再利用フロー
echo ""
echo "=== Issue #356: 既存 App 再利用フロー ==="

# assert 1: parseReuseApp が --reuse-app を検出し、無指定で false を返す
if node -e '
const s = require("./cli/setup");
if (s.parseReuseApp(["--reuse-app"]) !== true) process.exit(1);
if (s.parseReuseApp(["--owner", "alice"]) !== false) process.exit(1);
if (s.parseReuseApp([]) !== false) process.exit(1);
'; then
  pass "parseReuseApp が --reuse-app を検出し無指定で false（Issue #356）"
else
  fail "parseReuseApp の挙動が想定と異なる（Issue #356）"
fi

# assert 2: parseAppId が --app-id <n> / --app-id=<n> を取得し、不正値で null を返す
if node -e '
const s = require("./cli/setup");
if (s.parseAppId(["--app-id", "123"]) !== "123") process.exit(1);
if (s.parseAppId(["--app-id=456"]) !== "456") process.exit(1);
// 不正値: 0 / 先頭ゼロ / 非数値 / 空 / 負数 → null
if (s.parseAppId(["--app-id", "0"]) !== null) process.exit(1);
if (s.parseAppId(["--app-id", "01"]) !== null) process.exit(1);
if (s.parseAppId(["--app-id", "abc"]) !== null) process.exit(1);
if (s.parseAppId(["--app-id", ""]) !== null) process.exit(1);
if (s.parseAppId(["--app-id", "-5"]) !== null) process.exit(1);
if (s.parseAppId([]) !== null) process.exit(1);
'; then
  pass "parseAppId が正の整数のみ取得し不正値（0 / 先頭ゼロ / 非数値 / 空 / 負数）で null（Issue #356）"
else
  fail "parseAppId の検証が想定と異なる（Issue #356）"
fi

# assert 3: isValidAppId が正の整数のみ true（フラグ/対話で共有する単一述語、CISO M-1）
if node -e '
const s = require("./cli/setup");
if (s.isValidAppId("1") !== true) process.exit(1);
if (s.isValidAppId("9999999") !== true) process.exit(1);
if (s.isValidAppId("0") !== false) process.exit(1);
if (s.isValidAppId("01") !== false) process.exit(1);
if (s.isValidAppId("") !== false) process.exit(1);
if (s.isValidAppId("12a") !== false) process.exit(1);
if (s.isValidAppId(null) !== false) process.exit(1);
'; then
  pass "isValidAppId が正の整数のみ true（フラグ/対話で共有する単一述語、CISO M-1）"
else
  fail "isValidAppId の挙動が想定と異なる（Issue #356）"
fi

# assert 4: buildSteps({ reuseApp: true }) の第 1 ステップが app-reuse で app-create を含まない
if node -e '
const s = require("./cli/setup");
const steps = s.buildSteps({ owner: "alice", repo: "alice/bob", reuseApp: true });
if (steps.length !== 7) { console.error("expected 7 steps, got", steps.length); process.exit(1); }
if (steps[0].id !== "app-reuse") { console.error("first step must be app-reuse, got", steps[0].id); process.exit(1); }
if (steps.some((x) => x.id === "app-create")) { console.error("app-create must not exist in reuse mode"); process.exit(1); }
// 第 2 ステップ以降は新規モードと共通（app-logo が index 1）
if (steps[1].id !== "app-logo") { console.error("second step must be app-logo, got", steps[1].id); process.exit(1); }
'; then
  pass "buildSteps({ reuseApp: true }) が 7 ステップで第 1=app-reuse・app-create 不在・第 2=app-logo（Issue #356）"
else
  fail "buildSteps({ reuseApp: true }) の構造が想定と異なる（Issue #356）"
fi

# assert 5: buildSteps()（reuseApp 無指定）が従来通り app-create を第 1 ステップに持つ（後方互換）
if node -e '
const s = require("./cli/setup");
const steps = s.buildSteps({ owner: "alice", repo: "alice/bob" });
if (steps.length !== 7) process.exit(1);
if (steps[0].id !== "app-create") { console.error("default first step must be app-create, got", steps[0].id); process.exit(1); }
if (steps.some((x) => x.id === "app-reuse")) { console.error("app-reuse must not exist in default mode"); process.exit(1); }
'; then
  pass "buildSteps()（reuseApp 無指定）が第 1=app-create を維持（後方互換、Issue #356）"
else
  fail "buildSteps() のデフォルト挙動が変わった（後方互換違反、Issue #356）"
fi

# assert 6: app-reuse.run が clack / spawnSync を呼ばず、充足/未充足 state で正しく分岐する（CISO L-2 / architect #3）
if node -e '
const cp = require("child_process");
const orig = cp.spawnSync;
let spawnCalled = false;
cp.spawnSync = function() { spawnCalled = true; return { status: 0, stdout: "", stderr: "" }; };
const s = require("./cli/setup");
const steps = s.buildSteps({ owner: "alice", repo: "alice/bob", reuseApp: true });
const reuse = steps[0];
(async () => {
  const ok = await reuse.run({ appIdString: "123", credentials: { id: 123, name: "vibehawk-for-alice" } });
  const ng = await reuse.run({});
  cp.spawnSync = orig;
  if (spawnCalled) { console.error("app-reuse.run must NOT call spawnSync"); process.exit(1); }
  if (!ok || ok.ok !== true) { console.error("populated state must return ok:true"); process.exit(1); }
  if (!ng || ng.ok !== false) { console.error("empty state must return ok:false"); process.exit(1); }
})();
' > /dev/null 2>&1; then
  pass "app-reuse.run が spawnSync を呼ばず充足/未充足で {ok:true}/{ok:false} を返す（CISO L-2 / architect #3）"
else
  fail "app-reuse.run が spawnSync を呼ぶ or state 分岐が想定と異なる（Issue #356）"
fi

# assert 7: reuse モードで app-install / secret-pem の getUrl が state.credentials から正しい URL を生成
if node -e '
const s = require("./cli/setup");
const steps = s.buildSteps({ owner: "alice", repo: "alice/bob", reuseApp: true });
const cred = { id: 123, name: "vibehawk-for-alice", slug: "vibehawk-for-alice", html_url: "https://github.com/apps/vibehawk-for-alice" };
const state = { credentials: cred, appIdString: "123" };
const install = steps.find((x) => x.id === "app-install");
const pem = steps.find((x) => x.id === "secret-pem");
if (install.getUrl(state) !== "https://github.com/apps/vibehawk-for-alice/installations/new") { console.error("app-install url wrong:", install.getUrl(state)); process.exit(1); }
if (pem.getUrl(state) !== "https://github.com/settings/apps/vibehawk-for-alice") { console.error("secret-pem url wrong:", pem.getUrl(state)); process.exit(1); }
'; then
  pass "reuse モードで app-install / secret-pem の getUrl が state.credentials から正しい URL を生成（Issue #356）"
else
  fail "reuse モードの getUrl が想定 URL を生成しない（Issue #356）"
fi

# assert 8: 再利用フローで run() が state.appIdString に "null" 文字列を混入させない（CISO M-1 機械検証）
# --reuse-app かつ不正 --app-id を渡すと、parseAppId は null を返す。
# 対話入力もできない（clack モックで isCancel false / 空文字を返すと validate で弾かれるが、
# ここでは run() が "null"/"undefined"/"NaN" 文字列を state に書かないことを設計コードで検証する。
# state 充足直前の Number.isInteger 再ガードで不正値は process.exit(1) になる。
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/setup.js", "utf8");
// reuseApp 充足ブロックに Number.isInteger 再ガードがあること
if (!/if\s*\(reuseApp\)\s*\{[\s\S]*?Number\.isInteger\(appId\)/.test(src)) {
  console.error("state 充足ブロックに Number.isInteger 再ガードがない");
  process.exit(1);
}
// state.appIdString = String(appId)（検証済み数値）であり String(reuseAppId) を直接代入しないこと
if (/state\.appIdString\s*=\s*String\(reuseAppId\)/.test(src)) {
  console.error("state.appIdString に未検証の reuseAppId を直接代入している");
  process.exit(1);
}
if (!/state\.appIdString\s*=\s*String\(appId\)/.test(src)) {
  console.error("state.appIdString = String(appId)（検証済み数値）になっていない");
  process.exit(1);
}
'; then
  pass "run() の state 充足が Number.isInteger 再ガード後に String(appId) を使い \"null\" 混入を防ぐ（CISO M-1）"
else
  fail "run() の state 充足に Number.isInteger 再ガードがない or 未検証値を代入している（CISO M-1 違反）"
fi

# assert 9: setup.js が gh secret set / 書込系 gh api を呼ばない（再利用フロー追加後も CISO Critical 維持）
if grep -vE '^\s*(//|\*)' cli/setup.js | grep -E "spawnSync\(['\"]gh['\"][^)]*secret[^)]*set|['\"]--method['\"][[:space:]]*,[[:space:]]*['\"](PUT|POST|DELETE)['\"]" > /dev/null; then
  fail "setup.js が gh secret set / 書込系 gh api を呼ぶ（再利用フロー追加で CISO Critical 違反）"
else
  pass "setup.js は再利用フロー追加後も gh secret set / 書込系 gh api を呼ばない（CISO Critical 維持）"
fi

# assert 10: docs/troubleshooting.md に既存 App 再利用の項が追加されている
if grep -F "2 つ目以降のリポジトリ導入: 既存 App を再利用する" docs/troubleshooting.md > /dev/null; then
  pass "docs/troubleshooting.md に既存 App 再利用の項が追加されている（Issue #356 完了条件）"
else
  fail "docs/troubleshooting.md に既存 App 再利用の項がない（Issue #356 完了条件違反）"
fi

# assert 11: 再利用案内に「削除せず再利用」「App ID 入力」「Private Key 生成」の導線がある
declare -a REUSE_KEYWORDS=(
  "削除して作り直す必要はない"
  "App ID を入力"
  "Generate a private key"
  "--reuse-app"
)
for kw in "${REUSE_KEYWORDS[@]}"; do
  if grep -F -- "$kw" docs/troubleshooting.md > /dev/null; then
    pass "troubleshooting.md に再利用導線キーワード '$kw' が含まれる（Issue #356）"
  else
    fail "troubleshooting.md に再利用導線キーワード '$kw' がない（Issue #356）"
  fi
done

# Issue #361: secret-token の run() をスピナーで包まないことでトークン貼り付けプロンプトが表示される
# 根本原因: executeStep が run フェーズで clack.spinner() を start 直後に await step.run(state) するため、
# secret-token の run()（oauth.setupToken → readline）の貼り付けプロンプトがスピナー描画に上書きされ
# 画面に出なかった。修正: interactiveRun: true のステップはスピナーを生成しない。
echo "=== Issue #361: OAuth トークン貼り付けプロンプト表示（スピナー競合解消）検証 ==="

# assert 1: secret-token ステップが interactiveRun: true を持つ
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const t = steps.find((s) => s.id === "secret-token");
if (!t) { console.error("secret-token step not found"); process.exit(1); }
if (t.interactiveRun !== true) { console.error("secret-token must have interactiveRun: true, got:", t.interactiveRun); process.exit(1); }
'; then
  pass "secret-token ステップが interactiveRun: true を持つ（Issue #361: スピナー非使用の宣言）"
else
  fail "secret-token ステップに interactiveRun: true がない（Issue #361）"
fi

# assert 2: executeStep の run フェーズがスピナーを interactiveRun で条件分岐し、s.stop を null ガードする
if node -e '
const fs = require("fs");
const src = fs.readFileSync("cli/setup.js", "utf8");
const m = src.match(/async function executeStep[\s\S]*?\n\}/);
if (!m) { console.error("executeStep not found"); process.exit(1); }
const body = m[0];
if (!/interactiveRun/.test(body)) { console.error("executeStep does not reference interactiveRun"); process.exit(1); }
// スピナー生成が条件付き（... ? clack.spinner() : null）であること
if (!/clack\.spinner\(\)\s*:\s*null/.test(body)) { console.error("spinner creation is not conditional (... ? clack.spinner() : null)"); process.exit(1); }
// s.stop が if (s) でガードされていること（少なくとも 1 箇所）
if (!/if\s*\(s\)\s*s\.stop/.test(body)) { console.error("s.stop is not guarded with if (s)"); process.exit(1); }
'; then
  pass "executeStep が run スピナーを interactiveRun で条件分岐し s.stop を null ガードする（Issue #361 / architect 指摘①）"
else
  fail "executeStep のスピナー条件分岐 / s.stop null ガードが不足（Issue #361 / architect 指摘①）"
fi

# assert 3: secret-token の getInstructions が登録手順・Secret 名・クリップボード貼付を案内する（item 3）
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const t = steps.find((s) => s.id === "secret-token");
const instr = t.getInstructions();
if (typeof instr !== "string" || instr.length === 0) { console.error("getInstructions must return non-empty string"); process.exit(1); }
if (!/CLAUDE_CODE_OAUTH_TOKEN/.test(instr)) { console.error("must mention Secret name"); process.exit(1); }
if (!/登録/.test(instr)) { console.error("must distinguish registration step"); process.exit(1); }
if (!/クリップボード|Cmd\+V|Ctrl\+V/.test(instr)) { console.error("must mention clipboard paste"); process.exit(1); }
'; then
  pass "secret-token の getInstructions が登録手順・Secret 名・クリップボード貼付を案内する（Issue #361 item 3）"
else
  fail "secret-token の getInstructions が登録案内を欠く（Issue #361 item 3）"
fi

# assert 4: secret-token の run() が clack スピナー非アクティブ下で実行される（貼り付けプロンプトが上書きされない）
# clack.spinner モックで active 状態を追跡し、oauth.setupToken モック内で run 実行時に active でないことを検証する。
if node -e '
process.env.NODE_NO_WARNINGS = "1";

let spinnerActive = false;
let runDuringSpinner = false;

require.cache[require.resolve("@clack/prompts")] = {
  exports: {
    intro: () => {},
    outro: () => {},
    text: async () => "",
    select: async () => "skip",
    note: () => {},
    spinner: () => ({ start: () => { spinnerActive = true; }, stop: () => { spinnerActive = false; } }),
    cancel: () => {},
    isCancel: () => false,
    group: async () => {},
  },
};

const cp = require("child_process");
cp.spawnSync = function() { return { status: 0, stdout: "{}", stderr: "" }; };

require.cache[require.resolve("./cli/install")] = {
  exports: {
    run: async () => ({ id: 12345, name: "vibehawk-for-test", html_url: "https://github.com/apps/vibehawk-for-test", slug: "vibehawk-for-test" }),
    createWorkflowPr: async () => ({ url: "https://github.com/test/test/pull/1" }),
  },
};

require.cache[require.resolve("./cli/verify")] = {
  exports: {
    verifySecret: () => ({ ok: true, reason: "found", hint: "" }),
    verifyAppInstallation: () => ({ ok: true, reason: "installed_via_user", hint: "" }),
    verifyWorkflow: () => ({ ok: true, reason: "found", hint: "" }),
  },
};

require.cache[require.resolve("./cli/oauth")] = {
  exports: {
    setupToken: async () => {
      if (spinnerActive) runDuringSpinner = true;
      return { repo: "test/test", token: "X".repeat(40), settingsUrl: "https://github.com/test/test/settings/secrets/actions/new", clipboardCopied: true };
    },
    copyToClipboard: () => ({ success: true }),
    parseRepoArg: () => "test/test",
  },
};

const setup = require("./cli/setup");
setup.run({ argv: ["--owner", "test", "--repo", "test/test"] }).then(() => {
  if (runDuringSpinner) { console.error("spinner was active during secret-token run() (paste prompt would be overwritten)"); process.exit(1); }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "secret-token の run() が clack スピナー非アクティブ下で実行される（Issue #361: 貼り付けプロンプトが上書きされない）"
else
  fail "secret-token の run() がスピナー active 下で実行される / 完走しない（Issue #361 回帰）"
fi

# Issue #359: secret-pem ステップが Secrets 登録ページ URL も案内する
# secret-app-id は Secrets 登録 URL を案内するのに secret-pem は App 設定ページ URL だけで、
# .pem ダウンロード後の貼り付け先が分からない不整合があった。getInstructions に登録 URL を追記する。
echo "=== Issue #359: VIBEHAWK_PRIVATE_KEY の Secrets 登録 URL 案内検証 ==="

# assert 1: secret-pem の getInstructions が Secrets 登録ページ URL（settings/secrets/actions/new）を含む
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const pem = steps.find((s) => s.id === "secret-pem");
const instr = pem.getInstructions({ credentials: { slug: "vibehawk-for-alice" } });
if (typeof instr !== "string" || instr.length === 0) { console.error("getInstructions must return non-empty string"); process.exit(1); }
if (!instr.includes("https://github.com/alice/bob/settings/secrets/actions/new")) {
  console.error("getInstructions must include Secrets registration URL, got:", instr);
  process.exit(1);
}
if (!/VIBEHAWK_PRIVATE_KEY/.test(instr)) { console.error("must mention Secret name"); process.exit(1); }
'; then
  pass "secret-pem の getInstructions が Secrets 登録ページ URL を案内する（Issue #359）"
else
  fail "secret-pem の getInstructions が Secrets 登録ページ URL を案内しない（Issue #359）"
fi

# assert 2: secret-pem の getInstructions が鍵生成（App 設定ページ）と登録（Secrets ページ）の 2 段を区別する
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const pem = steps.find((s) => s.id === "secret-pem");
const instr = pem.getInstructions({ credentials: { slug: "vibehawk-for-alice" } });
// 鍵生成（Generate a private key）と登録（Secrets 登録）の両方の文言が含まれること
if (!/Generate a private key/.test(instr)) { console.error("must mention key generation step"); process.exit(1); }
if (!/登録/.test(instr)) { console.error("must mention registration step"); process.exit(1); }
'; then
  pass "secret-pem の getInstructions が鍵生成と登録の 2 段を区別する（Issue #359）"
else
  fail "secret-pem の getInstructions が 2 段を区別しない（Issue #359）"
fi

# assert 3: secret-pem の getUrl は App 設定ページ（settings/apps/<slug>）のまま不変（Issue #112 回帰防止）
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const pem = steps.find((s) => s.id === "secret-pem");
const url = pem.getUrl({ credentials: { slug: "vibehawk-for-alice" } });
if (url !== "https://github.com/settings/apps/vibehawk-for-alice") {
  console.error("getUrl must remain settings/apps/<slug>, got:", url);
  process.exit(1);
}
'; then
  pass "secret-pem の getUrl は settings/apps/<slug> のまま不変（Issue #359 / #112 回帰防止）"
else
  fail "secret-pem の getUrl が変わった（Issue #112 回帰）"
fi

# Issue #360: app-logo ステップが macOS でロゴ画像を Finder に表示する（非 macOS / 失敗時はフォールバック）
# パス文字列の表示だけだった app-logo に run を追加し、darwin で open -R によりロゴを Finder 選択表示する。
# best-effort のため open 不在 / 失敗 / 非 macOS でもウィザードを止めずパス表示にフォールバックする。
echo "=== Issue #360: ロゴ画像の Finder 自動表示検証 ==="

# assert 1: app-logo ステップが run を持ち、呼び出すと {ok:true} を返す（platform 問わず落ちない）
# spawnSync は setup.js が require 時に分割代入するため、require 前にモックを差し込む。
if node -e '
const cp = require("child_process");
cp.spawnSync = function() { return { status: 0, stdout: "", stderr: "" }; };
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const logo = steps.find((s) => s.id === "app-logo");
if (typeof logo.run !== "function") { console.error("app-logo must have a run function"); process.exit(1); }
logo.run().then((r) => {
  if (!r || r.ok !== true) { console.error("app-logo.run must return { ok: true }, got:", JSON.stringify(r)); process.exit(1); }
  if (typeof r.info !== "string" || r.info.length === 0) { console.error("run must return info string"); process.exit(1); }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "app-logo ステップが run を持ち {ok:true} を返す（Issue #360）"
else
  fail "app-logo ステップの run が無い / {ok:true} を返さない（Issue #360）"
fi

# assert 2: run の Finder 表示が platform 分岐する（darwin は open -R を呼び、非 darwin は呼ばない）
if node -e '
const cp = require("child_process");
let calledWith = null;
cp.spawnSync = function(cmd, args) { calledWith = { cmd, args }; return { status: 0, stdout: "", stderr: "" }; };
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const logo = steps.find((s) => s.id === "app-logo");
logo.run().then(() => {
  if (process.platform === "darwin") {
    if (!calledWith || calledWith.cmd !== "open" || calledWith.args[0] !== "-R") {
      console.error("darwin must call open -R, got:", JSON.stringify(calledWith)); process.exit(1);
    }
  } else {
    if (calledWith !== null) { console.error("non-darwin must not call spawnSync, got:", JSON.stringify(calledWith)); process.exit(1); }
  }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "app-logo の run が platform 分岐する（darwin: open -R / 非 darwin: 呼ばない）（Issue #360）"
else
  fail "app-logo の run の platform 分岐が想定と異なる（Issue #360）"
fi

# assert 3: open 失敗（status≠0）でも run は {ok:true} でパス表示にフォールバックする（ウィザードを止めない）
if node -e '
const cp = require("child_process");
cp.spawnSync = function() { return { status: 1, stdout: "", stderr: "open failed" }; };
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const logo = steps.find((s) => s.id === "app-logo");
logo.run().then((r) => {
  if (!r || r.ok !== true) { console.error("run must stay ok:true on open failure"); process.exit(1); }
  if (!/ロゴ画像の場所/.test(r.info)) { console.error("run must fall back to path display on failure, got:", r.info); process.exit(1); }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
' > /dev/null 2>&1; then
  pass "app-logo の run が open 失敗時もパス表示にフォールバックし {ok:true} を保つ（Issue #360）"
else
  fail "app-logo の run が open 失敗時にフォールバックしない / 落ちる（Issue #360）"
fi

# assert 4: app-logo の verify は manual_confirmation のまま、getValue を持たない・isSensitive:false（Issue #249 回帰防止）
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
const logo = steps.find((s) => s.id === "app-logo");
const v = logo.verify({ credentials: { slug: "vibehawk-for-alice" } });
if (!v || v.ok !== true || v.reason !== "manual_confirmation") { console.error("verify must stay manual_confirmation"); process.exit(1); }
if (typeof logo.getValue === "function") { console.error("app-logo must NOT define getValue"); process.exit(1); }
if (logo.isSensitive !== false) { console.error("app-logo isSensitive must stay false"); process.exit(1); }
'; then
  pass "app-logo の verify は manual_confirmation のまま getValue 不在・isSensitive:false（Issue #360 / #249 回帰防止）"
else
  fail "app-logo の verify / getValue / isSensitive が変わった（Issue #249 回帰）"
fi

# Issue #362: 同梱ロゴが正方形枠で角まで隙間なく表示される（四隅が白く抜けない）
# 旧ロゴは黒円 + 白い四隅で、GitHub の正方形アイコン枠だと角が白く抜けた。四隅を円と同じ dark で
# 埋めた。read-png-corners.js（依存ゼロ PNG デコーダ）で四隅が dark（白でない）ことを検証する。
echo "=== Issue #362: ロゴ四隅の正方形化検証 ==="

# assert 1: 四隅 4 点が dark（各チャンネル < 64）で白く抜けていない
if corners=$(node tests/read-png-corners.js assets/vibehawk-logo.png); then
  if node -e '
const s = process.argv[1];
const nums = (s.match(/[0-9]+/g) || []).map(Number);
if (nums.length < 12) { console.error("expected 12 channel values (4 corners x RGB), got:", s); process.exit(1); }
const bright = nums.filter((v) => v >= 64);
if (bright.length > 0) { console.error("a corner channel is too bright (white corner not filled):", s); process.exit(1); }
' "$corners"; then
    pass "ロゴの四隅 4 点が dark で白く抜けていない（Issue #362: 正方形化）"
  else
    fail "ロゴの四隅が白く抜けている（Issue #362: 正方形化が未反映）"
  fi
else
  fail "read-png-corners.js がロゴの四隅を読み取れない（Issue #362）"
fi

# assert 2: read-png-corners.js が 4 隅 12 値を出力できる（ヘルパー自体の健全性、PNG デコード成立）
if node tests/read-png-corners.js assets/vibehawk-logo.png | grep -qE '^tl=[0-9]+,[0-9]+,[0-9]+ tr=[0-9]+,[0-9]+,[0-9]+ bl=[0-9]+,[0-9]+,[0-9]+ br=[0-9]+,[0-9]+,[0-9]+$'; then
  pass "read-png-corners.js が四隅 RGB を所定フォーマットで出力する（PNG デコード成立）"
else
  fail "read-png-corners.js の出力フォーマットが想定と異なる（PNG デコード失敗の可能性）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
