#!/usr/bin/env bash
# tests/test_test_workflow_verify_matrix_result.sh
#
# scripts/ci/test/verify-matrix-result.sh の単体テスト（Issue #179）。
#
# 検証内容:
#   1. MATRIX_RESULT 未設定で exit 非 0（必須環境変数）
#   2. MATRIX_RESULT=success → exit 0
#   3. MATRIX_RESULT=cancelled → exit 0（concurrency キャンセル等は許容）
#   4. MATRIX_RESULT=failure → exit 1
#   5. MATRIX_RESULT=skipped → exit 1
#   6. shebang / set -euo pipefail を備える

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/test/verify-matrix-result.sh"

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

echo "=== scripts/ci/test/verify-matrix-result.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "verify-matrix-result.sh が存在する"
else
  fail "verify-matrix-result.sh が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

first_line="$(head -n 1 "$SCRIPT")"
if [[ "$first_line" == "#!/usr/bin/env bash" ]]; then
  pass "shebang が #!/usr/bin/env bash"
else
  fail "shebang が想定外: $first_line"
fi

if grep -qE "^set -euo pipefail$" "$SCRIPT"; then
  pass "set -euo pipefail を備える"
else
  fail "set -euo pipefail がない"
fi

set +e
env -u MATRIX_RESULT bash "$SCRIPT" > /dev/null 2>&1
exit_code=$?
set -e
if [[ "$exit_code" -ne 0 ]]; then
  pass "MATRIX_RESULT 未設定 → exit 非 0 ($exit_code)"
else
  fail "MATRIX_RESULT 未設定でも成功してしまう"
fi

set +e
output=$(MATRIX_RESULT=success bash "$SCRIPT" 2>&1)
exit_code=$?
set -e
if [[ "$exit_code" -eq 0 ]]; then
  pass "MATRIX_RESULT=success → exit 0"
else
  fail "success なのに exit $exit_code"
fi
if grep -qF "test-matrix: success" <<< "$output"; then
  pass "success 時メッセージが出力される"
else
  fail "success 時メッセージが想定と異なる: $output"
fi

set +e
output=$(MATRIX_RESULT=cancelled bash "$SCRIPT" 2>&1)
exit_code=$?
set -e
if [[ "$exit_code" -eq 0 ]]; then
  pass "MATRIX_RESULT=cancelled → exit 0"
else
  fail "cancelled なのに exit $exit_code"
fi
if grep -qF "test-matrix: cancelled" <<< "$output"; then
  pass "cancelled 時メッセージが出力される"
else
  fail "cancelled 時メッセージが想定と異なる: $output"
fi

set +e
output=$(MATRIX_RESULT=failure bash "$SCRIPT" 2>&1)
exit_code=$?
set -e
if [[ "$exit_code" -eq 1 ]]; then
  pass "MATRIX_RESULT=failure → exit 1"
else
  fail "failure なのに exit $exit_code"
fi
if grep -qF "test-matrix が失敗しました: failure" <<< "$output"; then
  pass "failure 時メッセージが出力される"
else
  fail "failure 時メッセージが想定と異なる: $output"
fi

set +e
output=$(MATRIX_RESULT=skipped bash "$SCRIPT" 2>&1)
exit_code=$?
set -e
if [[ "$exit_code" -eq 1 ]]; then
  pass "MATRIX_RESULT=skipped → exit 1"
else
  fail "skipped なのに exit $exit_code"
fi
if grep -qF "test-matrix が失敗しました: skipped" <<< "$output"; then
  pass "skipped 時メッセージが出力される"
else
  fail "skipped 時メッセージが想定と異なる: $output"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
