#!/usr/bin/env bash
# Issue #229 — .github/scripts/check-pr-title.sh の単体テスト

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/check-pr-title.sh"

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
  PR_TITLE="$1" GITHUB_OUTPUT="$out" bash "$SCRIPT" > /dev/null
  grep -e '^title_check_status=' "$out" | cut -d= -f2-
}

echo "Case 1: 絵文字 + CC prefix + コロン → passed"
status="$(run_check "✨ feat: 新機能追加")"
if [ "$status" = "passed" ]; then pass "Case 1"; else fail "Case 1: $status"; fi

echo "Case 2: CC prefix のみ（絵文字なし）→ passed"
status="$(run_check "fix: バグ修正")"
if [ "$status" = "passed" ]; then pass "Case 2"; else fail "Case 2: $status"; fi

echo "Case 3: scope 付き → passed"
status="$(run_check "🐛 fix(auth): 認証バグ")"
if [ "$status" = "passed" ]; then pass "Case 3"; else fail "Case 3: $status"; fi

echo "Case 4: CC prefix なし → failed"
status="$(run_check "ただのタイトル")"
if [ "$status" = "failed" ]; then pass "Case 4"; else fail "Case 4: $status"; fi

echo "Case 5: release prefix (vibehawk リリース PR) → passed"
status="$(run_check "🚀 release: epic #225 vibehawk sticky walkthrough")"
if [ "$status" = "passed" ]; then pass "Case 5"; else fail "Case 5: $status"; fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
