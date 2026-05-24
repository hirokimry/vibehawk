#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/check-secrets.sh 単体テスト（Issue #177）
#
# 検証対象:
#   - 3 secrets 全揃いで ready=true、missing 行は出さない
#   - 1 つ欠落で ready=false、missing= 行に欠落した変数名が入る
#   - 複数欠落でも先頭スペースを除いた状態で missing= に並ぶ
#   - 全欠落で 3 つの変数名が並ぶ
#   - 欠落時に ::warning:: が stdout に出力される（GitHub Actions の警告注釈）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/check-secrets.sh"

PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/vibehawk-chat/check-secrets.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "check-secrets.sh が存在する"
else
  fail "check-secrets.sh が存在しない"
  exit 1
fi

TMP1="$(mktemp)"
trap 'rm -f "$TMP1"' EXIT
APP_ID=app PRIVATE_KEY=key OAUTH_TOKEN=token GITHUB_OUTPUT="$TMP1" \
  bash "$SCRIPT" > /dev/null
if grep -Fxq "ready=true" "$TMP1" && ! grep -q "^missing=" "$TMP1"; then
  pass "3 secrets 全揃い → ready=true、missing 行なし"
else
  fail "3 secrets 全揃い時の出力が想定と異なる: $(tr '\n' '|' < "$TMP1")"
fi

TMP2="$(mktemp)"
APP_ID="" PRIVATE_KEY=key OAUTH_TOKEN=token GITHUB_OUTPUT="$TMP2" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -Fxq "ready=false" "$TMP2" && grep -Fxq "missing=VIBEHAWK_APP_ID" "$TMP2"; then
  pass "1 つ欠落 (APP_ID) → ready=false、missing=VIBEHAWK_APP_ID"
else
  fail "1 つ欠落時の出力が想定と異なる: $(tr '\n' '|' < "$TMP2")"
fi
rm -f "$TMP2"

TMP3="$(mktemp)"
APP_ID="" PRIVATE_KEY="" OAUTH_TOKEN=token GITHUB_OUTPUT="$TMP3" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -Fxq "ready=false" "$TMP3" && grep -Fxq "missing=VIBEHAWK_APP_ID VIBEHAWK_PRIVATE_KEY" "$TMP3"; then
  pass "2 つ欠落 → 先頭スペース除去された missing 行（順序固定）"
else
  fail "2 つ欠落時の出力が想定と異なる: $(tr '\n' '|' < "$TMP3")"
fi
rm -f "$TMP3"

TMP4="$(mktemp)"
APP_ID="" PRIVATE_KEY="" OAUTH_TOKEN="" GITHUB_OUTPUT="$TMP4" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -Fxq "ready=false" "$TMP4" && \
   grep -Fxq "missing=VIBEHAWK_APP_ID VIBEHAWK_PRIVATE_KEY CLAUDE_CODE_OAUTH_TOKEN" "$TMP4"; then
  pass "全欠落 → 3 つの変数名が missing 行に並ぶ"
else
  fail "全欠落時の出力が想定と異なる: $(tr '\n' '|' < "$TMP4")"
fi
rm -f "$TMP4"

TMP5="$(mktemp)"
warning_out="$(APP_ID="" PRIVATE_KEY="" OAUTH_TOKEN="" GITHUB_OUTPUT="$TMP5" \
  bash "$SCRIPT" 2>&1)"
if echo "$warning_out" | grep -F "::warning::vibehawk chat: 未設定 secret(s):" > /dev/null; then
  pass "欠落時に ::warning:: 注釈が出力される"
else
  fail "::warning:: 注釈が出力されない: '$warning_out'"
fi
rm -f "$TMP5"

TMP6="$(mktemp)"
warning_out2="$(APP_ID=a PRIVATE_KEY=b OAUTH_TOKEN=c GITHUB_OUTPUT="$TMP6" \
  bash "$SCRIPT" 2>&1)"
if [[ -z "$warning_out2" ]]; then
  pass "全揃い時には ::warning:: が出ない"
else
  fail "全揃い時に余計な出力: '$warning_out2'"
fi
rm -f "$TMP6"

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
