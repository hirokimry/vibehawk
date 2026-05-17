#!/usr/bin/env bash
# scripts/ci/vibehawk-review/post-placeholder-comment.sh の単体テスト。
#
# gh CLI スタブで gh pr comment の呼び出し引数を捕捉し、本文に必須の secret 名
# 3 種と利用者向け案内文が含まれることを検証する。

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

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/post-placeholder-comment.sh"

echo "=== scripts/ci/vibehawk-review/post-placeholder-comment.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "post-placeholder-comment.sh が存在する"
else
  fail "post-placeholder-comment.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
# gh スタブ: 受け取った全引数を 1 行ずつ stdout に出力する
for arg in "$@"; do
  printf '%s\n' "$arg"
done
EOF
chmod +x "$STUB_DIR/gh"

# 1. 正常系: gh pr comment が呼ばれ、必須要素を含む
out="$(PATH="$STUB_DIR:$PATH" PR_NUMBER=42 MISSING="VIBEHAWK_APP_ID CLAUDE_CODE_OAUTH_TOKEN" \
       bash "$SCRIPT" 2>&1)"
if echo "$out" | grep -qx "pr" \
   && echo "$out" | grep -qx "comment" \
   && echo "$out" | grep -qx "42"; then
  pass "gh pr comment 42 が呼ばれる"
else
  fail "gh pr comment の呼び出しが想定と異なる: '$out'"
fi

if echo "$out" | grep -qF "🦅 vibehawk: 未設定 secret(s):" \
   && echo "$out" | grep -qF "VIBEHAWK_APP_ID CLAUDE_CODE_OAUTH_TOKEN" \
   && echo "$out" | grep -qF "Settings → Secrets and variables → Actions"; then
  pass "コメント本文に必須案内文を含む"
else
  fail "コメント本文が想定と異なる: '$out'"
fi

# 2. PR_NUMBER 未設定 → 非 0 終了
set +e
err_out="$(PATH="$STUB_DIR:$PATH" MISSING="X" bash "$SCRIPT" 2>&1)"
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]] && echo "$err_out" | grep -qF "PR_NUMBER"; then
  pass "PR_NUMBER 未設定で非 0 終了する"
else
  fail "PR_NUMBER 未設定時の挙動が想定と異なる: rc=$err_rc, out='$err_out'"
fi

# 3. MISSING 未設定 → 非 0 終了
set +e
err_out="$(PATH="$STUB_DIR:$PATH" PR_NUMBER=42 bash "$SCRIPT" 2>&1)"
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]] && echo "$err_out" | grep -qF "MISSING"; then
  pass "MISSING 未設定で非 0 終了する"
else
  fail "MISSING 未設定時の挙動が想定と異なる: rc=$err_rc, out='$err_out'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
