#!/usr/bin/env bash
# Issue #229 — .github/scripts/check-pr-description.sh の単体テスト

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/check-pr-description.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

TMP_OUTPUTS=()
cleanup() {
  for f in "${TMP_OUTPUTS[@]+"${TMP_OUTPUTS[@]}"}"; do rm -f "$f" || true; done
}
trap cleanup EXIT

run_check() {
  local out
  out="$(mktemp)"
  TMP_OUTPUTS+=("$out")
  PR_BODY="$1" GITHUB_OUTPUT="$out" bash "$SCRIPT" > /dev/null
  grep -e '^description_check_status=' "$out" | cut -d= -f2-
}

echo "Case 1: Closes #N + ## 見出し → passed"
status="$(run_check $'## 概要\nテスト\n\nCloses #226')"
if [ "$status" = "passed" ]; then pass "Case 1"; else fail "Case 1: $status"; fi

echo "Case 2: Refs #N + ## 見出し → passed"
status="$(run_check $'## 背景\nテスト\n\nRefs #225')"
if [ "$status" = "passed" ]; then pass "Case 2"; else fail "Case 2: $status"; fi

echo "Case 3: Issue 参照なし → failed"
status="$(run_check $'## 概要\nテスト本文のみ')"
if [ "$status" = "failed" ]; then pass "Case 3"; else fail "Case 3: $status"; fi

echo "Case 4: ## 見出しなし → failed"
status="$(run_check $'Closes #100\n本文')"
if [ "$status" = "failed" ]; then pass "Case 4"; else fail "Case 4: $status"; fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
