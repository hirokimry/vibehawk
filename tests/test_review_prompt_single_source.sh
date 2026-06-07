#!/usr/bin/env bash
# レビュー基準の単一ソース化を検証する（Issue #330）
#
# - 共通ファイル templates/review-prompt.md が存在する
# - CI プロンプト .github/prompts/vibehawk-review.md が include マーカーで共通ファイルを参照する
# - レビュー基準が CI プロンプト原本に直接二重保持されていない（単一ソース）
# - include 展開後（envsubst 前）の出力が切り出し前の golden とバイト一致する（挙動不変）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARED="${REPO_ROOT}/templates/review-prompt.md"
CI_PROMPT="${REPO_ROOT}/.github/prompts/vibehawk-review.md"
GOLDEN="${REPO_ROOT}/tests/fixtures/vibehawk-review-prompt.golden.md"
EXPAND="${REPO_ROOT}/.github/scripts/expand-prompt-includes.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "Case 1: 共通ファイル templates/review-prompt.md が存在する"
if [[ -f "$SHARED" ]]; then
  pass "Case 1"
else
  fail "Case 1: 共通ファイルが存在しない"
  exit 1
fi

echo "Case 2: golden fixture が存在する"
if [[ -f "$GOLDEN" ]]; then
  pass "Case 2"
else
  fail "Case 2: golden fixture が存在しない"
  exit 1
fi

echo "Case 3: CI プロンプトが include マーカーで共通ファイルを参照する"
if grep -qF '<!-- vibehawk:include templates/review-prompt.md -->' "$CI_PROMPT"; then
  pass "Case 3"
else
  fail "Case 3: CI プロンプトに include マーカーが無い"
fi

echo "Case 4: レビュー基準が CI プロンプト原本に二重保持されていない（単一ソース）"
# severity 5 段階分類の見出しは共通ファイルに移動済み。CI プロンプト原本には残っていないはず。
if grep -qF '## inline 指摘の severity 5 段階分類' "$CI_PROMPT"; then
  fail "Case 4: レビュー基準が CI プロンプトに二重保持されている"
else
  pass "Case 4"
fi

echo "Case 5: 基準内容が共通ファイル側に存在する"
if grep -qF '## inline 指摘の severity 5 段階分類' "$SHARED" \
  && grep -qF '🔴 | Critical' "$SHARED"; then
  pass "Case 5"
else
  fail "Case 5: 共通ファイルにレビュー基準が無い"
fi

echo "Case 6: include 展開後（envsubst 前）が golden とバイト一致する（挙動不変）"
expanded="$(mktemp)"
trap 'rm -f "$expanded" || true' EXIT
cd "$REPO_ROOT"
"$EXPAND" "$CI_PROMPT" > "$expanded" 2>/dev/null
if cmp -s "$GOLDEN" "$expanded"; then
  pass "Case 6"
else
  fail "Case 6: 展開後が golden とバイト不一致（挙動が変わっている）"
  diff "$GOLDEN" "$expanded" | head -20
fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
