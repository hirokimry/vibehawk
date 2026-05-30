#!/usr/bin/env bash
# Issue #10: vibehawk-review.yml の vibehawk_config ステップで使う
# size_limits → depth 切替ロジックの単体テスト

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

calc_depth() {
  local fc="$1"
  local full="${2:-30}"
  local focused="${3:-80}"
  local skip="${4:-3000}"

  if [[ "$fc" -ge "$skip" ]]; then
    echo "summary_only"
  elif [[ "$fc" -ge "$focused" ]]; then
    echo "lightweight"
  elif [[ "$fc" -ge "$full" ]]; then
    echo "focused"
  else
    echo "full"
  fi
}

echo "=== デフォルト閾値 (30 / 80 / 3000) での depth 判定 ==="

for fc in 0 5 10 29; do
  result="$(calc_depth "$fc")"
  if [[ "$result" == "full" ]]; then
    pass "FILES_COUNT=$fc → depth=full"
  else
    fail "FILES_COUNT=$fc の depth が想定と異なる: '$result' (期待: full)"
  fi
done

for fc in 30 50 79; do
  result="$(calc_depth "$fc")"
  if [[ "$result" == "focused" ]]; then
    pass "FILES_COUNT=$fc → depth=focused"
  else
    fail "FILES_COUNT=$fc の depth が想定と異なる: '$result' (期待: focused)"
  fi
done

for fc in 80 100 1000 2999; do
  result="$(calc_depth "$fc")"
  if [[ "$result" == "lightweight" ]]; then
    pass "FILES_COUNT=$fc → depth=lightweight"
  else
    fail "FILES_COUNT=$fc の depth が想定と異なる: '$result' (期待: lightweight)"
  fi
done

for fc in 3000 5000 100000; do
  result="$(calc_depth "$fc")"
  if [[ "$result" == "summary_only" ]]; then
    pass "FILES_COUNT=$fc → depth=summary_only"
  else
    fail "FILES_COUNT=$fc の depth が想定と異なる: '$result' (期待: summary_only)"
  fi
done

echo "=== カスタム閾値（.vibehawk.yaml で上書き） ==="

result="$(calc_depth 5 10 50 200)"
if [[ "$result" == "full" ]]; then
  pass "カスタム閾値: 5 ファイル → full"
else
  fail "カスタム閾値の挙動が想定と異なる: '$result'"
fi

result="$(calc_depth 10 10 50 200)"
if [[ "$result" == "focused" ]]; then
  pass "カスタム閾値: 10 ファイル（境界値） → focused"
else
  fail "カスタム閾値の挙動が想定と異なる: '$result'"
fi

result="$(calc_depth 100 10 50 200)"
if [[ "$result" == "lightweight" ]]; then
  pass "カスタム閾値: 100 ファイル → lightweight"
else
  fail "カスタム閾値の挙動が想定と異なる: '$result'"
fi

result="$(calc_depth 250 10 50 200)"
if [[ "$result" == "summary_only" ]]; then
  pass "カスタム閾値: 250 ファイル → summary_only"
else
  fail "カスタム閾値の挙動が想定と異なる: '$result'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
