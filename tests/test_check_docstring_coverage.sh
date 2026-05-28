#!/usr/bin/env bash
# Issue #229 — .github/scripts/check-docstring-coverage.sh の単体テスト
# v1 は言語不問で skipped 固定出力するため最小検証のみ。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/check-docstring-coverage.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

GITHUB_OUTPUT="$TMP" bash "$SCRIPT" > /dev/null
status="$(grep -e '^docstring_check_status=' "$TMP" | cut -d= -f2-)"
explanation="$(grep -e '^docstring_check_explanation=' "$TMP" | cut -d= -f2-)"

echo "Case 1: v1 は skipped 固定"
if [ "$status" = "skipped" ]; then pass "Case 1"; else fail "Case 1: $status"; fi

echo "Case 2: explanation に理由が含まれる"
if printf '%s' "$explanation" | grep -qF '別 Issue'; then pass "Case 2"; else fail "Case 2: $explanation"; fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
