#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/post-placeholder.sh 単体テスト（Issue #177）
#
# gh CLI を PATH スタブで差し替え、想定の引数で gh issue comment が
# 呼び出されるかを検証する（実際の GitHub API 呼び出しは行わない）。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/post-placeholder.sh"

PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/vibehawk-chat/post-placeholder.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "post-placeholder.sh が存在する"
else
  fail "post-placeholder.sh が存在しない"
  exit 1
fi

STUB_DIR="$(mktemp -d)"
LOG_FILE="$(mktemp)"
trap 'rm -rf "$STUB_DIR" "$LOG_FILE"' EXIT

cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
# gh スタブ: 受け取った引数を 1 行 1 引数で LOG_FILE に追記する
for arg in "\$@"; do
  printf '%s\n' "\$arg" >> "$LOG_FILE"
done
EOF
chmod +x "$STUB_DIR/gh"

PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy \
  ISSUE_NUMBER=42 \
  MISSING="VIBEHAWK_APP_ID VIBEHAWK_PRIVATE_KEY" \
  bash "$SCRIPT" > /dev/null

if grep -Fxq "issue" "$LOG_FILE" && grep -Fxq "comment" "$LOG_FILE" && grep -Fxq "42" "$LOG_FILE"; then
  pass "gh issue comment <ISSUE_NUMBER> 形式で呼び出される"
else
  fail "gh issue comment の引数が想定と異なる: $(tr '\n' '|' < "$LOG_FILE")"
fi

if grep -Fxq -- "--body" "$LOG_FILE"; then
  pass "--body フラグが渡される"
else
  fail "--body フラグが不在"
fi

if grep -F "VIBEHAWK_APP_ID VIBEHAWK_PRIVATE_KEY" "$LOG_FILE" > /dev/null; then
  pass "body 本文に MISSING の値が埋め込まれる"
else
  fail "body 本文に MISSING の値が埋め込まれない"
fi

if grep -F "のため応答をスキップしました" "$LOG_FILE" > /dev/null; then
  pass "body 本文に「のため応答をスキップしました」を含む（仕様文言）"
else
  fail "body 本文の仕様文言が欠落"
fi

if grep -F "3 secrets" "$LOG_FILE" > /dev/null && \
   grep -F "Settings で設定してください" "$LOG_FILE" > /dev/null; then
  pass "body 本文に 3 secrets 設定案内が含まれる"
else
  fail "body 本文の 3 secrets 設定案内が不足"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
