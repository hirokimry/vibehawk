#!/usr/bin/env bash
# tests/test_test_workflow_run_all_tests.sh
#
# scripts/ci/test/run-all-tests.sh の単体テスト（Issue #179）。
#
# 検証内容:
#   1. tests/test_*.sh が存在しない場合に exit 1 で終わる
#   2. 全テストが pass する場合に exit 0 で終わる
#   3. 1 件でも fail するテストがあれば exit 1 で終わる
#   4. shebang / set -euo pipefail を備える

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/test/run-all-tests.sh"

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

echo "=== scripts/ci/test/run-all-tests.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "run-all-tests.sh が存在する"
else
  fail "run-all-tests.sh が存在しない"
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

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "${TMPDIR_TEST}/case_empty"
set +e
( cd "${TMPDIR_TEST}/case_empty" && bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -eq 1 ]]; then
  pass "テストファイルなし → exit 1"
else
  fail "テストファイルなし → 想定 exit 1 だが実際は $exit_code"
fi

mkdir -p "${TMPDIR_TEST}/case_all_pass/tests"
cat > "${TMPDIR_TEST}/case_all_pass/tests/test_ok1.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${TMPDIR_TEST}/case_all_pass/tests/test_ok2.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${TMPDIR_TEST}/case_all_pass/tests/"test_*.sh
set +e
( cd "${TMPDIR_TEST}/case_all_pass" && bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -eq 0 ]]; then
  pass "全テスト pass → exit 0"
else
  fail "全テスト pass → 想定 exit 0 だが実際は $exit_code"
fi

mkdir -p "${TMPDIR_TEST}/case_one_fail/tests"
cat > "${TMPDIR_TEST}/case_one_fail/tests/test_ok.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${TMPDIR_TEST}/case_one_fail/tests/test_ng.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${TMPDIR_TEST}/case_one_fail/tests/"test_*.sh
set +e
( cd "${TMPDIR_TEST}/case_one_fail" && bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -eq 1 ]]; then
  pass "1 件 fail → exit 1"
else
  fail "1 件 fail → 想定 exit 1 だが実際は $exit_code"
fi

mkdir -p "${TMPDIR_TEST}/case_glob/tests"
cat > "${TMPDIR_TEST}/case_glob/tests/test_ok.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${TMPDIR_TEST}/case_glob/tests/helper_should_be_ignored.sh" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
chmod +x "${TMPDIR_TEST}/case_glob/tests/"*.sh
set +e
( cd "${TMPDIR_TEST}/case_glob" && bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -eq 0 ]]; then
  pass "test_*.sh パターン外は実行されない"
else
  fail "test_*.sh パターン外も実行されている（exit $exit_code）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
