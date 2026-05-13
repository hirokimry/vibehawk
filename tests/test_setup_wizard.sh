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

# 必須ファイル存在
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

# setup.js: buildSteps が STEPS.length === 6 を返す
if node -e '
const setup = require("./cli/setup");
const steps = setup.buildSteps({ owner: "alice", repo: "alice/bob" });
if (!Array.isArray(steps)) process.exit(1);
if (steps.length !== 6) { console.error("expected 6 steps, got:", steps.length); process.exit(1); }
// secret-token ステップが isSensitive: true
const tokenStep = steps.find((s) => s.id === "secret-token");
if (!tokenStep || tokenStep.isSensitive !== true) { console.error("secret-token must have isSensitive: true (CISO Critical)"); process.exit(1); }
// secret-app-id / app-install は isSensitive: false
for (const id of ["app-install", "secret-app-id"]) {
  const s = steps.find((x) => x.id === id);
  if (!s || s.isSensitive !== false) { console.error(id, "must have isSensitive: false"); process.exit(1); }
}
'; then
  pass "buildSteps が 6 ステップを返し secret-token に isSensitive: true が付与されている（CISO Critical）"
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

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
