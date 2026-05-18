#!/usr/bin/env bash
# tests/test_shellcheck_run_scripts_ci.sh
# scripts/ci/shellcheck/run-scripts-ci.sh の単体テスト

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/ci/shellcheck/run-scripts-ci.sh"
PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/shellcheck/run-scripts-ci.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "run-scripts-ci.sh が存在する"
else
  fail "run-scripts-ci.sh が存在しない"
  exit 1
fi

if [[ -x "$SCRIPT" ]]; then
  pass "実行権限が付与されている"
else
  fail "実行権限が付与されていない"
fi

if grep -qF "set -euo pipefail" "$SCRIPT"; then
  pass "set -euo pipefail を備える"
else
  fail "set -euo pipefail が無い"
fi

if grep -qE "shellcheck --severity=warning --shell=bash" "$SCRIPT"; then
  pass "shellcheck を severity=warning + shell=bash で呼ぶ"
else
  fail "shellcheck の呼び出しが想定と異なる"
fi

if grep -qF 'scripts/ci/**/*.sh' "$SCRIPT"; then
  pass "scripts/ci/**/*.sh を対象にしている"
else
  fail "scripts/ci/**/*.sh が対象になっていない"
fi

# scripts/ci/ にシェルが無い空ディレクトリで実行 → exit 1
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "${TMP_ROOT}/scripts/ci"
set +e
(cd "$TMP_ROOT" && bash "$SCRIPT") > "${TMP_ROOT}/out" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]] && grep -qF "scripts/ci/ 配下にシェルがない" "${TMP_ROOT}/out"; then
  pass "scripts/ci/ にシェルが無いとき exit 1 + エラーメッセージ"
else
  fail "scripts/ci/ 空ディレクトリ時の挙動が想定と異なる: rc=$rc, out='$(cat "${TMP_ROOT}/out")'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
