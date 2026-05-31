#!/usr/bin/env bash
# Issue #281: mark-outside-diff.sh のテスト
#
# 検証対象: scripts/ci/vibehawk-review/mark-outside-diff.sh
# - PR の patch から「コメント可能行（RIGHT/LEFT）」を算出し、範囲外の comment に
#   _outside_diff: true を付与する。FILES_JSON env で patch を注入してテストする（gh 不要）。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/mark-outside-diff.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

TMPDIR_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_ROOT" || true; }
trap cleanup EXIT

if [[ -f "$SCRIPT" ]]; then
  pass "mark-outside-diff.sh が存在する"
else
  fail "mark-outside-diff.sh が存在しない"
  exit 1
fi

# 機能: payload と FILES_JSON を与えて実行し、各 comment の _outside_diff を返す
run_mark() {
  local payload="${TMPDIR_ROOT}/payload.json"
  printf '%s' "$1" > "$payload"
  FILES_JSON="$2" bash "$SCRIPT" "$payload" > /dev/null
  jq -c '[.comments[] | {line, path, outside: ._outside_diff}]' "$payload"
}

# a.sh: 新ファイル行 9(context),10,11,12(added) が hunk 内。
PATCH_FILES='[{"filename":"a.sh","patch":"@@ -9,1 +9,4 @@\n ctx9\n+new10\n+new11\n+new12"},{"filename":"bin.dat","patch":null}]'

echo "=== Case 1: in-diff の RIGHT 行は outside=false ==="
out="$(run_mark '{"comments":[{"path":"a.sh","line":10,"side":"RIGHT"}]}' "$PATCH_FILES")"
if [[ "$(jq -r '.[0].outside' <<< "$out")" == "false" ]]; then
  pass "hunk 内の追加行（10）は outside=false"
else
  fail "in-diff 行が outside=false にならない: $out"
fi

echo "=== Case 2: 範囲外の RIGHT 行は outside=true ==="
out="$(run_mark '{"comments":[{"path":"a.sh","line":99,"side":"RIGHT"}]}' "$PATCH_FILES")"
if [[ "$(jq -r '.[0].outside' <<< "$out")" == "true" ]]; then
  pass "hunk 外の行（99）は outside=true"
else
  fail "範囲外行が outside=true にならない: $out"
fi

echo "=== Case 3: context 行（commentable）は outside=false ==="
out="$(run_mark '{"comments":[{"path":"a.sh","line":9}]}' "$PATCH_FILES")"
if [[ "$(jq -r '.[0].outside' <<< "$out")" == "false" ]]; then
  pass "context 行（9）は outside=false"
else
  fail "context 行が outside=false にならない: $out"
fi

echo "=== Case 4: diff に無いファイルは outside=true ==="
out="$(run_mark '{"comments":[{"path":"c.sh","line":3}]}' "$PATCH_FILES")"
if [[ "$(jq -r '.[0].outside' <<< "$out")" == "true" ]]; then
  pass "diff 対象外ファイルは outside=true"
else
  fail "diff 外ファイルが outside=true にならない: $out"
fi

echo "=== Case 5: patch が null（バイナリ等）のファイルは outside=true ==="
out="$(run_mark '{"comments":[{"path":"bin.dat","line":1}]}' "$PATCH_FILES")"
if [[ "$(jq -r '.[0].outside' <<< "$out")" == "true" ]]; then
  pass "patch null ファイルは outside=true"
else
  fail "patch null ファイルが outside=true にならない: $out"
fi

echo "=== Case 6: 複数行範囲で start_line が範囲外なら outside=true ==="
out="$(run_mark '{"comments":[{"path":"a.sh","line":11,"start_line":8}]}' "$PATCH_FILES")"
if [[ "$(jq -r '.[0].outside' <<< "$out")" == "true" ]]; then
  pass "start_line(8) が範囲外なら範囲指摘全体を outside=true"
else
  fail "範囲外 start_line が outside=true にならない: $out"
fi

echo "=== Case 7: LEFT 側の削除行は outside=false ==="
# 旧ファイル行 9 が削除（-）。LEFT でコメント可能。
LEFT_FILES='[{"filename":"d.sh","patch":"@@ -9,2 +9,1 @@\n ctx9\n-removed10"}]'
out="$(run_mark '{"comments":[{"path":"d.sh","line":10,"side":"LEFT"}]}' "$LEFT_FILES")"
if [[ "$(jq -r '.[0].outside' <<< "$out")" == "false" ]]; then
  pass "LEFT 側の削除行（旧 10）は outside=false"
else
  fail "LEFT 削除行が outside=false にならない: $out"
fi

echo "=== Case 8: comments 空でもエラーにならない ==="
if FILES_JSON="$PATCH_FILES" bash "$SCRIPT" <(echo '{"comments":[]}') > /dev/null 2>&1 \
   || { printf '{"comments":[]}' > "${TMPDIR_ROOT}/empty.json"; FILES_JSON="$PATCH_FILES" bash "$SCRIPT" "${TMPDIR_ROOT}/empty.json" > /dev/null; }; then
  pass "comments 空で正常終了"
else
  fail "comments 空でエラー終了"
fi

echo ""
echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
