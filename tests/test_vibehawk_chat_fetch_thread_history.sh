#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/fetch-thread-history.sh 単体テスト（Issue #177）
#
# gh CLI を PATH スタブで差し替え、ページネートされた複数ページの
# レスポンスを Issue 本文 + 全コメントとして結合できることを検証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/fetch-thread-history.sh"

PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/vibehawk-chat/fetch-thread-history.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "fetch-thread-history.sh が存在する"
else
  fail "fetch-thread-history.sh が存在しない"
  exit 1
fi

STUB_DIR="$(mktemp -d)"
GITHUB_OUTPUT_FILE="$(mktemp)"
trap 'rm -rf "$STUB_DIR" "$GITHUB_OUTPUT_FILE" /tmp/vibehawk-thread-9999.json /tmp/vibehawk-thread-9999.json.combined' EXIT

cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
# 引数列を結合
all="$*"
# --paginate 付き comments 呼び出し
if [[ "$all" == *"--paginate"* ]] && [[ "$all" == *"/comments"* ]]; then
  # --jq 'X' で射影済み形式（複数ページが連続）。ここでは 2 ページ分相当を出力。
  cat <<'JSON'
{"user":"alice","created_at":"2025-01-01T00:00:00Z","body":"comment 1"}
{"user":"bob","created_at":"2025-01-01T01:00:00Z","body":"comment 2"}
JSON
  exit 0
fi
# 単発 issues/<n> 呼び出し（issue 本文取得）
if [[ "$all" == *"/issues/"* ]] && [[ "$all" != *"/comments"* ]]; then
  cat <<'JSON'
{"user":"issue_author","created_at":"2024-12-31T23:00:00Z","body":"issue body"}
JSON
  exit 0
fi
echo "unexpected gh args: $all" >&2
exit 1
EOF
chmod +x "$STUB_DIR/gh"

# 実行
PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy \
  REPO="owner/repo" \
  ISSUE_NUMBER=9999 \
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
  bash "$SCRIPT" > /dev/null

HISTORY_FILE="/tmp/vibehawk-thread-9999.json"

# 1: history_file が GITHUB_OUTPUT に書かれる
if grep -Fxq "history_file=$HISTORY_FILE" "$GITHUB_OUTPUT_FILE"; then
  pass "GITHUB_OUTPUT に history_file=<path> が書かれる"
else
  fail "GITHUB_OUTPUT に history_file が書かれない: $(tr '\n' '|' < "$GITHUB_OUTPUT_FILE")"
fi

# 2: comment_count が GITHUB_OUTPUT に書かれる（Issue 本文 1 + コメント 2 = 3）
if grep -Fxq "comment_count=3" "$GITHUB_OUTPUT_FILE"; then
  pass "GITHUB_OUTPUT に comment_count=3 が書かれる（Issue 本文 + コメント 2）"
else
  fail "comment_count の値が想定と異なる: $(tr '\n' '|' < "$GITHUB_OUTPUT_FILE")"
fi

# 3: history_file の中身が JSON 配列で 3 要素
if [[ -f "$HISTORY_FILE" ]]; then
  count="$(jq 'length' "$HISTORY_FILE")"
  if [[ "$count" == "3" ]]; then
    pass "history_file の配列長が 3"
  else
    fail "history_file の配列長が想定と異なる: $count"
  fi
else
  fail "history_file が作成されていない"
fi

# 4: history_file の先頭要素が Issue 本文（時系列順序の起点）
if [[ -f "$HISTORY_FILE" ]]; then
  first_user="$(jq -r '.[0].user' "$HISTORY_FILE")"
  if [[ "$first_user" == "issue_author" ]]; then
    pass "history_file の先頭要素が Issue 本文（user=issue_author）"
  else
    fail "history_file の先頭要素が Issue 本文ではない: '$first_user'"
  fi
fi

# 5: history_file の 2 番目以降がコメント（時系列順）
if [[ -f "$HISTORY_FILE" ]]; then
  second_user="$(jq -r '.[1].user' "$HISTORY_FILE")"
  third_user="$(jq -r '.[2].user' "$HISTORY_FILE")"
  if [[ "$second_user" == "alice" && "$third_user" == "bob" ]]; then
    pass "history_file のコメントが時系列順で並ぶ（alice → bob）"
  else
    fail "history_file のコメント順序が想定と異なる: '$second_user', '$third_user'"
  fi
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
