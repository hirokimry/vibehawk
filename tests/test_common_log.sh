#!/usr/bin/env bash
# scripts/ci/common/log.sh の単体テスト。
#
# 各 log_* 関数を bash サブシェルで呼び出し、stdout/stderr の振り分けと
# プレフィックスを検証する。

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

LOG_SH="${REPO_ROOT}/scripts/ci/common/log.sh"

echo "=== scripts/ci/common/log.sh 単体テスト ==="

if [[ -f "$LOG_SH" ]]; then
  pass "scripts/ci/common/log.sh が存在する"
else
  fail "scripts/ci/common/log.sh が存在しない"
  exit 1
fi

info_out="$(bash -c "source '$LOG_SH'; log_info hello" 2>/dev/null)"
if [[ "$info_out" == "[INFO] hello" ]]; then
  pass "log_info が stdout に [INFO] プレフィックス付きで出力する"
else
  fail "log_info の出力が想定と異なる: '$info_out'"
fi

info_err="$(bash -c "source '$LOG_SH'; log_info hello" 2>&1 >/dev/null)"
if [[ -z "$info_err" ]]; then
  pass "log_info は stderr に出力しない"
else
  fail "log_info が stderr に出力した: '$info_err'"
fi

warn_err="$(bash -c "source '$LOG_SH'; log_warn careful" 2>&1 >/dev/null)"
if [[ "$warn_err" == "[WARN] careful" ]]; then
  pass "log_warn が stderr に [WARN] プレフィックス付きで出力する"
else
  fail "log_warn の stderr 出力が想定と異なる: '$warn_err'"
fi

warn_out="$(bash -c "source '$LOG_SH'; log_warn careful" 2>/dev/null)"
if [[ -z "$warn_out" ]]; then
  pass "log_warn は stdout に出力しない"
else
  fail "log_warn が stdout に出力した: '$warn_out'"
fi

err_err="$(bash -c "source '$LOG_SH'; log_error boom" 2>&1 >/dev/null)"
if [[ "$err_err" == "[ERROR] boom" ]]; then
  pass "log_error が stderr に [ERROR] プレフィックス付きで出力する"
else
  fail "log_error の stderr 出力が想定と異なる: '$err_err'"
fi

err_out="$(bash -c "source '$LOG_SH'; log_error boom" 2>/dev/null)"
if [[ -z "$err_out" ]]; then
  pass "log_error は stdout に出力しない"
else
  fail "log_error が stdout に出力した: '$err_out'"
fi

multi_out="$(bash -c "source '$LOG_SH'; log_info one two three" 2>/dev/null)"
if [[ "$multi_out" == "[INFO] one two three" ]]; then
  pass "log_info が複数引数をスペース区切りで結合する"
else
  fail "log_info の複数引数挙動が想定と異なる: '$multi_out'"
fi

loaded_marker="$(bash -c "source '$LOG_SH'; echo \"\$VIBEHAWK_CI_LOG_LOADED\"")"
if [[ "$loaded_marker" == "1" ]]; then
  pass "source 後に VIBEHAWK_CI_LOG_LOADED が 1 になる"
else
  fail "多重 source 防止のマーカーが想定と異なる: '$loaded_marker'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
