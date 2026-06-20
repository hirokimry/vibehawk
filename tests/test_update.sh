#!/usr/bin/env bash
# Issue #371: npx vibehawk update（workflow を最新版に更新）の検証
# - index.js への登録 / help 表示
# - --repo 未指定で throw
# - install.createWorkflowPr({overwrite:true}) への委譲（App 作成 Manifest Flow を呼ばない）
# - {url} / {skipped} の表示分岐

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== vibehawk update コマンド検証 (Issue #371) ==="

# 前提: cli/update.js が存在する
if [[ -f cli/update.js ]]; then
  pass "cli/update.js が存在する"
else
  fail "cli/update.js が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# assert 1: index.js に update コマンドが登録されている
if grep -F "update: ()" cli/index.js > /dev/null; then
  pass "update コマンドが index.js に登録されている"
else
  fail "update コマンドが index.js に登録されていない"
fi

# assert 2: help に update が表示される
if node cli/index.js help 2>&1 | grep -F "npx vibehawk update" > /dev/null; then
  pass "CLI help が update コマンドを表示する"
else
  fail "CLI help が update コマンドを表示しない"
fi

# assert 3: update.run() が --repo 未指定で throw する
if node -e '
const update = require("./cli/update");
update.run({ argv: [] }).then(() => {
  console.error("should have thrown without --repo");
  process.exit(1);
}).catch(() => process.exit(0));
'; then
  pass "update.run() が --repo 未指定で throw する"
else
  fail "update.run() が --repo 未指定でも throw しない"
fi

# assert 4: update.run() が install.createWorkflowPr を overwrite:true + 正しい repo で呼び、install.run を呼ばない
if node -e '
let cwArgs = null;
let runCalled = false;
require.cache[require.resolve("./cli/install")] = {
  exports: {
    createWorkflowPr: async (opts) => { cwArgs = opts; return { url: "https://github.com/alice/bob/pull/1" }; },
    run: async () => { runCalled = true; return {}; },
  },
};
const update = require("./cli/update");
update.run({ argv: ["--repo", "alice/bob"] }).then(() => {
  if (!cwArgs || cwArgs.repo !== "alice/bob") { console.error("createWorkflowPr repo mismatch:", JSON.stringify(cwArgs)); process.exit(1); }
  if (cwArgs.overwrite !== true) { console.error("createWorkflowPr must be called with overwrite:true"); process.exit(1); }
  if (runCalled) { console.error("update must NOT call install.run (Manifest Flow / App 作成)"); process.exit(1); }
  process.exit(0);
}).catch((e) => { console.error(e.message); process.exit(1); });
'; then
  pass "update.run() が createWorkflowPr を overwrite:true で呼び install.run（App 作成）を呼ばない（Issue #371 核心）"
else
  fail "update.run() の委譲先 / App 作成回避が想定と異なる（Issue #371）"
fi

# assert 5: createWorkflowPr が {url} を返すと PR URL を表示する
if node -e '
require.cache[require.resolve("./cli/install")] = {
  exports: { createWorkflowPr: async () => ({ url: "https://github.com/alice/bob/pull/42" }), run: async () => ({}) },
};
const update = require("./cli/update");
update.run({ argv: ["--repo", "alice/bob"] }).then(() => process.exit(0)).catch((e) => { console.error(e.message); process.exit(1); });
' 2>&1 | grep -F "https://github.com/alice/bob/pull/42" > /dev/null; then
  pass "update.run() が PR URL を表示する"
else
  fail "update.run() が PR URL を表示しない"
fi

# assert 6: createWorkflowPr が {skipped} を返すとスキップ案内を表示する
if node -e '
require.cache[require.resolve("./cli/install")] = {
  exports: { createWorkflowPr: async () => ({ skipped: true, reason: "existing-files", existingFiles: ["x.yml"] }), run: async () => ({}) },
};
const update = require("./cli/update");
update.run({ argv: ["--repo", "alice/bob"] }).then(() => process.exit(0)).catch((e) => { console.error(e.message); process.exit(1); });
' 2>&1 | grep -F "スキップ" > /dev/null; then
  pass "update.run() が skipped 時にスキップ案内を表示する"
else
  fail "update.run() が skipped 時の案内を表示しない"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
