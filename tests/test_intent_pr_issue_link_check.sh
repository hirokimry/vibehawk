#!/usr/bin/env bash
# scripts/ci/intent-checks/pr-issue-link-check.sh の単体テスト。
#
# 実際の GitHub API 呼び出しは行わない（CI で gh 認証情報を必須にしないため）。
# PATH に gh スタブを差し込み、PR 本文のパース分岐を検証する。

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

SCRIPT="${REPO_ROOT}/scripts/ci/intent-checks/pr-issue-link-check.sh"

echo "=== scripts/ci/intent-checks/pr-issue-link-check.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "スクリプトが存在する"
else
  fail "スクリプトが存在しない"
  exit 1
fi

# 必須環境変数の検証
set +e
err_out="$(REPO=test/repo bash "$SCRIPT" 2>&1)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -qF "PR_NUMBER"; then
  pass "PR_NUMBER 未指定で非 0 終了"
else
  fail "PR_NUMBER バリデーション挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

# シナリオ 1: PR 本文に Issue 参照あり → exit 0
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
# PR body のみ返す
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  echo "Closes #123"
  exit 0
fi
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out="$(PATH="$STUB_DIR:$PATH" PR_NUMBER=999 REPO=test/repo bash "$SCRIPT" 2>&1)"
code=$?
set -e
if [[ $code -eq 0 ]] && echo "$out" | grep -qF "Issue 参照が見つかりました"; then
  pass "Issue 参照ありで exit 0"
else
  fail "Issue 参照あり分岐の挙動が想定と異なる: exit=$code, out='$out'"
fi

# シナリオ 2: ref キーワードでも検出（grep -i + refs?）
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  echo "Refs #456"
  exit 0
fi
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out2="$(PATH="$STUB_DIR:$PATH" PR_NUMBER=999 REPO=test/repo bash "$SCRIPT" 2>&1)"
code2=$?
set -e
if [[ $code2 -eq 0 ]]; then
  pass "Refs #N でも Issue 参照として検出"
else
  fail "Refs #N の検出に失敗: exit=$code2, out='$out2'"
fi

# シナリオ 3: PR 本文に Issue 参照なし → exit 1 + コメント投稿
cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
# pr view body はパース対象なし、pr comment は記録
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
  echo "This is a PR without issue reference"
  exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "comment" ]]; then
  echo "GH_PR_COMMENT_CALLED: \$*" >> "$STUB_DIR/calls.log"
  exit 0
fi
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out3="$(PATH="$STUB_DIR:$PATH" PR_NUMBER=999 REPO=test/repo bash "$SCRIPT" 2>&1)"
code3=$?
set -e
if [[ $code3 -eq 1 ]]; then
  pass "Issue 参照なしで exit 1"
else
  fail "Issue 参照なしの exit code が 1 ではない: exit=$code3, out='$out3'"
fi

if [[ -f "$STUB_DIR/calls.log" ]] && grep -qF "GH_PR_COMMENT_CALLED" "$STUB_DIR/calls.log"; then
  pass "Issue 参照なしで gh pr comment が呼ばれる"
else
  fail "gh pr comment が呼ばれていない"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
