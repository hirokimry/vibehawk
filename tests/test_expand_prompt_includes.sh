#!/usr/bin/env bash
# .github/scripts/expand-prompt-includes.sh の単体テスト（Issue #330）
#
# - include マーカーが参照先内容に展開される（単一 / 複数）
# - マーカー以外の行はそのまま出力される
# - include 先不在で exit 1 + 解決パス + 元ファイル:行番号 を含むエラー
# - 絶対パス / `..` traversal / 許可外 charset を拒否
# - 展開後に未展開マーカーが残らない

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/expand-prompt-includes.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

if [[ ! -x "$SCRIPT" ]]; then
  fail "${SCRIPT} が実行可能でない"
  exit 1
fi

# 一時作業ディレクトリは repo root 配下に作る（include 解決基点 = git repo root のため）。
WORKDIR="$(mktemp -d "${REPO_ROOT}/.tmp-expand-test.XXXXXX")"
cleanup() {
  rm -rf "$WORKDIR" || true
}
trap cleanup EXIT

# include 先（repo root 相対パスで参照させる）。WORKDIR は repo root 直下。
rel="$(basename "$WORKDIR")"
printf 'INCLUDED-LINE-1\nINCLUDED-LINE-2\n' > "${WORKDIR}/inc.md"

cd "$REPO_ROOT"

echo "Case 1: 単一マーカーが参照先内容に展開される"
src1="${WORKDIR}/src1.md"
printf 'HEAD\n<!-- vibehawk:include %s/inc.md -->\nTAIL\n' "$rel" > "$src1"
out1="$("$SCRIPT" "$src1" 2>/dev/null)"
expected1="$(printf 'HEAD\nINCLUDED-LINE-1\nINCLUDED-LINE-2\nTAIL')"
if [[ "$out1" == "$expected1" ]]; then
  pass "Case 1"
else
  fail "Case 1: 展開結果が不一致: $out1"
fi

echo "Case 2: 複数マーカーが全て展開される"
src2="${WORKDIR}/src2.md"
printf '<!-- vibehawk:include %s/inc.md -->\nMID\n<!-- vibehawk:include %s/inc.md -->\n' "$rel" "$rel" > "$src2"
out2="$("$SCRIPT" "$src2" 2>/dev/null)"
count2="$(printf '%s\n' "$out2" | grep -c 'INCLUDED-LINE-1')"
if [[ "$count2" -eq 2 ]] && printf '%s\n' "$out2" | grep -qF 'MID'; then
  pass "Case 2"
else
  fail "Case 2: 複数展開が不正（count=$count2）"
fi

echo "Case 3: 展開後に未展開マーカーが残らない"
if printf '%s\n' "$out1" "$out2" | grep -qF 'vibehawk:include'; then
  fail "Case 3: 未展開マーカーが残っている"
else
  pass "Case 3"
fi

echo "Case 4: マーカーの無いファイルはそのまま出力（パススルー）"
src4="${WORKDIR}/src4.md"
printf 'LINE-A\nLINE-B\n' > "$src4"
out4="$("$SCRIPT" "$src4" 2>/dev/null)"
if [[ "$out4" == "$(printf 'LINE-A\nLINE-B')" ]]; then
  pass "Case 4"
else
  fail "Case 4: パススルーが不正: $out4"
fi

echo "Case 5: include 先不在で exit 1 + 解決パス + 元ファイル:行番号"
src5="${WORKDIR}/src5.md"
printf 'X\n<!-- vibehawk:include %s/nope.md -->\n' "$rel" > "$src5"
set +e
err5="$("$SCRIPT" "$src5" 2>&1 >/dev/null)"
ec5=$?
set -e
if [[ $ec5 -ne 0 ]] \
  && printf '%s' "$err5" | grep -qF 'include 先が見つかりません' \
  && printf '%s' "$err5" | grep -qF "${rel}/nope.md" \
  && printf '%s' "$err5" | grep -qF "${src5}:2"; then
  pass "Case 5"
else
  fail "Case 5: ec=$ec5, err=$err5"
fi

echo "Case 6: 絶対パスを拒否（exit 1）"
src6="${WORKDIR}/src6.md"
printf '<!-- vibehawk:include /etc/passwd -->\n' > "$src6"
set +e
err6="$("$SCRIPT" "$src6" 2>&1 >/dev/null)"
ec6=$?
set -e
if [[ $ec6 -ne 0 ]] && printf '%s' "$err6" | grep -qF '絶対パス'; then
  pass "Case 6"
else
  fail "Case 6: ec=$ec6, err=$err6"
fi

echo "Case 7: .. traversal を拒否（exit 1）"
src7="${WORKDIR}/src7.md"
printf '<!-- vibehawk:include ../../etc/passwd -->\n' > "$src7"
set +e
err7="$("$SCRIPT" "$src7" 2>&1 >/dev/null)"
ec7=$?
set -e
if [[ $ec7 -ne 0 ]] && printf '%s' "$err7" | grep -qF '.. は使えません'; then
  pass "Case 7"
else
  fail "Case 7: ec=$ec7, err=$err7"
fi

echo "Case 8: 許可外 charset を拒否（exit 1）"
src8="${WORKDIR}/src8.md"
printf '<!-- vibehawk:include foo bar.md -->\n' > "$src8"
set +e
"$SCRIPT" "$src8" >/dev/null 2>&1
ec8=$?
set -e
# 注: スペースを含むため正規表現 `.+ -->$` のパス部に空白が入り charset 検証で弾かれる
if [[ $ec8 -ne 0 ]]; then
  pass "Case 8"
else
  fail "Case 8: 許可外文字が拒否されていない（ec=$ec8）"
fi

echo "Case 9: 展開対象ファイル自体が不在で exit 1"
set +e
err9="$("$SCRIPT" "${WORKDIR}/missing-src.md" 2>&1 >/dev/null)"
ec9=$?
set -e
if [[ $ec9 -ne 0 ]] && printf '%s' "$err9" | grep -qF '展開対象ファイルが見つかりません'; then
  pass "Case 9"
else
  fail "Case 9: ec=$ec9, err=$err9"
fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
