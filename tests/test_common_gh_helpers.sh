#!/usr/bin/env bash
# scripts/ci/common/gh-helpers.sh の単体テスト。
#
# 実際の GitHub API 呼び出しは行わない（CI で gh 認証情報を必須にしないため）。
# PATH に gh スタブを差し込み、ラッパー関数が想定通り `--paginate` 付きで
# gh を呼び出すかを検証する。

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

GH_HELPERS_SH="${REPO_ROOT}/scripts/ci/common/gh-helpers.sh"

echo "=== scripts/ci/common/gh-helpers.sh 単体テスト ==="

if [[ -f "$GH_HELPERS_SH" ]]; then
  pass "scripts/ci/common/gh-helpers.sh が存在する"
else
  fail "scripts/ci/common/gh-helpers.sh が存在しない"
  exit 1
fi

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  printf '%s\n' "$arg"
done
EOF
chmod +x "$STUB_DIR/gh"

out="$(PATH="$STUB_DIR:$PATH" bash -c "source '$GH_HELPERS_SH'; gh_api_paginated /repos/hirokimry/vibehawk/issues/175/comments")"
expected="api
--paginate
/repos/hirokimry/vibehawk/issues/175/comments"
if [[ "$out" == "$expected" ]]; then
  pass "gh_api_paginated が --paginate を付けて gh api を呼ぶ"
else
  fail "gh_api_paginated の出力が想定と異なる: '$out'"
fi

out2="$(PATH="$STUB_DIR:$PATH" bash -c "source '$GH_HELPERS_SH'; gh_api_paginated /repos/x/y/issues/1/comments '.[] | .body'")"
expected2="api
--paginate
/repos/x/y/issues/1/comments
--jq
.[] | .body"
if [[ "$out2" == "$expected2" ]]; then
  pass "gh_api_paginated が --jq を 2 引数目として渡す"
else
  fail "gh_api_paginated の jq_filter 引数挙動が想定と異なる: '$out2'"
fi

set +e
err_out="$(PATH="$STUB_DIR:$PATH" bash -c "source '$GH_HELPERS_SH'; gh_api_paginated" 2>&1)"
err_code=$?
set -e
if [[ $err_code -eq 2 ]] && echo "$err_out" | grep -F "[ERROR] gh_api_paginated: endpoint が必須です" > /dev/null; then
  pass "gh_api_paginated: endpoint 未指定で exit 2 + エラーログ"
else
  fail "gh_api_paginated の引数バリデーション挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

out3="$(PATH="$STUB_DIR:$PATH" bash -c "source '$GH_HELPERS_SH'; gh_issue_field 175 title")"
expected3="issue
view
175
--json
title
--jq
.title"
if [[ "$out3" == "$expected3" ]]; then
  pass "gh_issue_field が gh issue view --json <field> --jq .<field> を呼ぶ"
else
  fail "gh_issue_field の引数構築が想定と異なる: '$out3'"
fi

set +e
err_out2="$(PATH="$STUB_DIR:$PATH" bash -c "source '$GH_HELPERS_SH'; gh_issue_field 175" 2>&1)"
err_code2=$?
set -e
if [[ $err_code2 -eq 2 ]] && echo "$err_out2" | grep -F "[ERROR] gh_issue_field: issue_number と field_name が必須です" > /dev/null; then
  pass "gh_issue_field: 引数不足で exit 2 + エラーログ"
else
  fail "gh_issue_field の引数バリデーション挙動が想定と異なる: exit=$err_code2, out='$err_out2'"
fi

loaded_marker="$(bash -c "source '$GH_HELPERS_SH'; echo \"\$VIBEHAWK_CI_GH_HELPERS_LOADED\"")"
if [[ "$loaded_marker" == "1" ]]; then
  pass "source 後に VIBEHAWK_CI_GH_HELPERS_LOADED が 1 になる"
else
  fail "多重 source 防止マーカーが想定と異なる: '$loaded_marker'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
