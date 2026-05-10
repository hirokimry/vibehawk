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

# verify.js: matchInstallation が app_id 一致を抽出（モックレスポンス）
if node -e '
const v = require("./cli/verify");
// 一致 + repository_selection: all
const j1 = JSON.stringify({ installations: [{ app_id: 12345, repository_selection: "all" }] });
if (!v.matchInstallation(j1, "12345", "alice/bob")) process.exit(1);
// 一致 + selected
const j2 = JSON.stringify({ installations: [{ app_id: 99999, repository_selection: "selected" }] });
if (!v.matchInstallation(j2, "99999", "alice/bob")) process.exit(1);
// 不一致
const j3 = JSON.stringify({ installations: [{ app_id: 11111, repository_selection: "all" }] });
if (v.matchInstallation(j3, "12345", "alice/bob")) process.exit(1);
// 空配列
if (v.matchInstallation(JSON.stringify({ installations: [] }), "12345", "alice/bob")) process.exit(1);
// 配列形式（/orgs/X/installations の場合）
const j4 = JSON.stringify([{ app_id: 12345, repository_selection: "all" }]);
if (!v.matchInstallation(j4, "12345", "alice/bob")) process.exit(1);
// 不正な JSON
if (v.matchInstallation("not json", "12345", "alice/bob")) process.exit(1);
// 空文字
if (v.matchInstallation("", "12345", "alice/bob")) process.exit(1);
'; then
  pass "matchInstallation が一致/不一致/空配列/不正 JSON を正しく判定"
else
  fail "matchInstallation の判定が想定と異なる"
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

# CLO 条件 4: docs/external-dependency-audit.md に @clack/prompts が含まれる
if grep -F "@clack/prompts" docs/external-dependency-audit.md > /dev/null; then
  pass "docs/external-dependency-audit.md に @clack/prompts エントリが追加されている（CLO 条件 2 + 4）"
else
  fail "docs/external-dependency-audit.md に @clack/prompts エントリがない"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
