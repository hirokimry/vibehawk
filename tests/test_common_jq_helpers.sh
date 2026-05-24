#!/usr/bin/env bash
# scripts/ci/common/jq-helpers.sh の単体テスト。
#
# jq の実バイナリを使って結合・オブジェクト拡張の挙動を検証する。
# `\(...)` string interpolation を一切使っていないことも grep で確認する。

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

JQ_HELPERS_SH="${REPO_ROOT}/scripts/ci/common/jq-helpers.sh"

echo "=== scripts/ci/common/jq-helpers.sh 単体テスト ==="

if [[ -f "$JQ_HELPERS_SH" ]]; then
  pass "scripts/ci/common/jq-helpers.sh が存在する"
else
  fail "scripts/ci/common/jq-helpers.sh が存在しない"
  exit 1
fi

if ! command -v jq > /dev/null; then
  fail "jq が PATH に存在しない（CI runner 設定の問題）"
  exit 1
fi

out="$(bash -c "source '$JQ_HELPERS_SH'; jq_concat '件数: ' '42'")"
# jq 出力は double-quote 付き文字列
if [[ "$out" == '"件数: 42"' ]]; then
  pass "jq_concat が 2 引数を + で結合する"
else
  fail "jq_concat の 2 引数結合が想定と異なる: '$out'"
fi

out2="$(bash -c "source '$JQ_HELPERS_SH'; jq_concat 'PR #' '175' ' のレビュー'")"
if [[ "$out2" == '"PR #175 のレビュー"' ]]; then
  pass "jq_concat が 3 引数を + で結合する"
else
  fail "jq_concat の 3 引数結合が想定と異なる: '$out2'"
fi

out3="$(bash -c "source '$JQ_HELPERS_SH'; jq_concat 'single'")"
if [[ "$out3" == '"single"' ]]; then
  pass "jq_concat が 1 引数でも動く"
else
  fail "jq_concat の 1 引数挙動が想定と異なる: '$out3'"
fi

set +e
err_out="$(bash -c "source '$JQ_HELPERS_SH'; jq_concat" 2>&1)"
err_code=$?
set -e
if [[ $err_code -eq 2 ]] && echo "$err_out" | grep -F "[ERROR] jq_concat: 少なくとも 1 つの引数が必要です" > /dev/null; then
  pass "jq_concat: 引数 0 で exit 2 + エラーログ"
else
  fail "jq_concat の引数バリデーション挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

out4="$(bash -c "source '$JQ_HELPERS_SH'; jq_concat 'a \"quoted\" ' 'value with \$dollar'")"
expected4='"a \"quoted\" value with $dollar"'
if [[ "$out4" == "$expected4" ]]; then
  pass "jq_concat が特殊文字（quote / dollar）を安全に扱う"
else
  fail "jq_concat の特殊文字挙動が想定と異なる: 期待='$expected4', 実='$out4'"
fi

# jq_obj_set_str: jq -n が改行・空白を挿入することがあるため jq で正規化して比較
out5="$(bash -c "source '$JQ_HELPERS_SH'; jq_obj_set_str '{\"a\":1}' 'b' 'value'")"
normalized="$(echo "$out5" | jq -cS .)"
if [[ "$normalized" == '{"a":1,"b":"value"}' ]]; then
  pass "jq_obj_set_str が既存オブジェクトに文字列キーを追加する"
else
  fail "jq_obj_set_str の結果が想定と異なる: '$out5' (normalized: '$normalized')"
fi

out6="$(bash -c "source '$JQ_HELPERS_SH'; jq_obj_set_str '{}' 'k' 'v'")"
normalized6="$(echo "$out6" | jq -cS .)"
if [[ "$normalized6" == '{"k":"v"}' ]]; then
  pass "jq_obj_set_str が空オブジェクトに追加できる"
else
  fail "jq_obj_set_str (空オブジェクト) の結果が想定と異なる: '$out6'"
fi

set +e
err_out2="$(bash -c "source '$JQ_HELPERS_SH'; jq_obj_set_str '{}'" 2>&1)"
err_code2=$?
set -e
if [[ $err_code2 -eq 2 ]] && echo "$err_out2" | grep -F "[ERROR] jq_obj_set_str: base と key が必須です" > /dev/null; then
  pass "jq_obj_set_str: 引数不足で exit 2 + エラーログ"
else
  fail "jq_obj_set_str の引数バリデーション挙動が想定と異なる: exit=$err_code2, out='$err_out2'"
fi

# ヘルパー本体の実コード行に \( (jq string interpolation) が含まれないことを確認
# （コメント行は除外: awk で行頭 # 判定）
non_comment_interp="$(grep -nE '\\\(' "$JQ_HELPERS_SH" | grep -v '^[[:space:]]*[0-9]*[[:space:]]*:[[:space:]]*#' || true)"
non_comment_filtered="$(printf '%s\n' "$non_comment_interp" | awk -F: '{
  line=$0
  sub(/^[0-9]+:/, "", line)
  if (line ~ /^[[:space:]]*#/) next
  if (line == "") next
  print
}')"
if [[ -z "$non_comment_filtered" ]]; then
  pass "jq-helpers.sh の実コード行に jq string interpolation \\(...) がない"
else
  fail "jq-helpers.sh の実コード行に \\( が混入している:"$'\n'"$non_comment_filtered"
fi

loaded_marker="$(bash -c "source '$JQ_HELPERS_SH'; echo \"\$VIBEHAWK_CI_JQ_HELPERS_LOADED\"")"
if [[ "$loaded_marker" == "1" ]]; then
  pass "source 後に VIBEHAWK_CI_JQ_HELPERS_LOADED が 1 になる"
else
  fail "多重 source 防止マーカーが想定と異なる: '$loaded_marker'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
