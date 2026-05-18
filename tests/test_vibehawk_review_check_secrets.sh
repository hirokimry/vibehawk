#!/usr/bin/env bash
# scripts/ci/vibehawk-review/check-secrets.sh の単体テスト。
#
# 3 secrets の組み合わせ（全揃え / 一部欠落 / 全欠落）に対して、
# GITHUB_OUTPUT 出力と stdout の ::warning:: 行をそれぞれ検証する。

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

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/check-secrets.sh"

echo "=== scripts/ci/vibehawk-review/check-secrets.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "check-secrets.sh が存在する"
else
  fail "check-secrets.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_script() {
  # Usage: run_script APP_ID PRIVATE_KEY OAUTH_TOKEN
  local app="${1:-}" key="${2:-}" tok="${3:-}"
  local output_file="${TMP_DIR}/github_output"
  : > "$output_file"
  local stdout_file="${TMP_DIR}/stdout"
  local rc=0
  APP_ID="$app" PRIVATE_KEY="$key" OAUTH_TOKEN="$tok" \
    GITHUB_OUTPUT="$output_file" \
    bash "$SCRIPT" > "$stdout_file" 2>&1 || rc=$?
  echo "$rc"
}

# 1. 全 secrets が設定されている → ready=true
rc=$(run_script "app123" "private456" "token789")
out_file="${TMP_DIR}/github_output"
if [[ "$rc" -eq 0 ]] && grep -qx "ready=true" "$out_file" && ! grep -q "missing=" "$out_file"; then
  pass "全 secrets 設定時に ready=true を出力する"
else
  fail "全揃え時の出力が想定と異なる: rc=$rc, output=$(cat "$out_file")"
fi

# 2. APP_ID のみ欠落 → ready=false, missing=VIBEHAWK_APP_ID
rc=$(run_script "" "private456" "token789")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "ready=false" "$out_file" \
   && grep -qx "missing=VIBEHAWK_APP_ID" "$out_file"; then
  pass "APP_ID 欠落時に missing=VIBEHAWK_APP_ID を出力する"
else
  fail "APP_ID 欠落時の出力が想定と異なる: rc=$rc, output=$(cat "$out_file")"
fi

# 3. 全 secrets 欠落 → ready=false, missing= 3 つ全部（スペース区切り）
rc=$(run_script "" "" "")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "ready=false" "$out_file" \
   && grep -qx "missing=VIBEHAWK_APP_ID VIBEHAWK_PRIVATE_KEY CLAUDE_CODE_OAUTH_TOKEN" "$out_file"; then
  pass "全欠落時に missing 3 つを空白区切りで出力する"
else
  fail "全欠落時の出力が想定と異なる: rc=$rc, output=$(cat "$out_file")"
fi

# 4. 全欠落時に ::warning:: が stdout に出る
stdout_content="$(cat "${TMP_DIR}/stdout")"
if echo "$stdout_content" | grep -qF "::warning::vibehawk: 未設定 secret(s):"; then
  pass "全欠落時に ::warning:: を stdout に出力する"
else
  fail "全欠落時に ::warning:: が出力されなかった: stdout='$stdout_content'"
fi

# 5. 全揃え時には ::warning:: が出ない
rc=$(run_script "app123" "private456" "token789")
stdout_content="$(cat "${TMP_DIR}/stdout")"
if ! echo "$stdout_content" | grep -qF "::warning::"; then
  pass "全揃え時には ::warning:: を出力しない"
else
  fail "全揃え時に ::warning:: が出てしまった: stdout='$stdout_content'"
fi

# 6. GITHUB_OUTPUT 未設定だと早期失敗する（set -u + : ${VAR:?msg}）
# GitHub Actions runner では GITHUB_OUTPUT が親シェル env から子へ継承されるため、
# 単に「assign しない」だけでは不十分。env -u GITHUB_OUTPUT で子 env から明示除去する（PR #185 と同じパターン）。
set +e
err_out="$(env -u GITHUB_OUTPUT APP_ID=a PRIVATE_KEY=b OAUTH_TOKEN=c bash "$SCRIPT" 2>&1)"
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]] && echo "$err_out" | grep -qF "GITHUB_OUTPUT"; then
  pass "GITHUB_OUTPUT 未設定で非 0 終了する"
else
  fail "GITHUB_OUTPUT 未設定時の挙動が想定と異なる: rc=$err_rc, out='$err_out'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
