#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/post-status-check.sh 単体テスト（Issue #177）
#
# 検証対象:
#   - APPROVED review → conclusion=success
#   - CHANGES_REQUESTED review → conclusion=failure
#   - その他 (COMMENTED 等) → conclusion=neutral
#   - review 未投稿 → conclusion=neutral + 専用 title/summary
#   - substantive review filter: 空 COMMENTED review に引きずられない

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/post-status-check.sh"

PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/vibehawk-chat/post-status-check.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "post-status-check.sh が存在する"
else
  fail "post-status-check.sh が存在しない"
  exit 1
fi

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

make_stub() {
  local review_json="$1"
  local pull_json="$2"
  local log_file="$3"
  cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
all="\$*"
for arg in "\$@"; do
  printf 'ARG:%s\n' "\$arg" >> "$log_file"
done
# pulls/<n>/reviews（--paginate あり）
if [[ "\$all" == *"/reviews"* ]]; then
  cat <<'JSON'
$review_json
JSON
  exit 0
fi
# pulls/<n>（HEAD_SHA 用、--jq '.head.sha'）
if [[ "\$all" == *"/pulls/"* ]] && [[ "\$all" != *"/reviews"* ]]; then
  if [[ "\$all" == *"--jq"* ]]; then
    echo "$pull_json"
    exit 0
  fi
fi
# check-runs POST はログだけ
if [[ "\$all" == *"check-runs"* ]]; then
  exit 0
fi
echo "unexpected gh args: \$all" >&2
exit 1
EOF
  chmod +x "$STUB_DIR/gh"
}

LOG1="$(mktemp)"
make_stub '[{"user":{"login":"vibehawk-for-owner[bot]"},"state":"APPROVED","body":"OK","submitted_at":"2025-01-01T00:00:00Z"}]' \
  "abc123sha" \
  "$LOG1"
PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO="owner/repo" PR_NUMBER=200 OWNER="owner" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -Fxq "ARG:conclusion=success" "$LOG1"; then
  pass "APPROVED review → conclusion=success（check-runs POST）"
else
  fail "APPROVED 時の conclusion が想定と異なる: $(tr '\n' '|' < "$LOG1" | head -c 500)"
fi
if grep -F "output[title]=vibehawk: APPROVED" "$LOG1" > /dev/null; then
  pass "APPROVED 時の output[title] に APPROVED 文字列が含まれる"
else
  fail "APPROVED 時の title が想定と異なる"
fi
rm -f "$LOG1"

LOG2="$(mktemp)"
make_stub '[{"user":{"login":"vibehawk-for-owner[bot]"},"state":"CHANGES_REQUESTED","body":"修正してください","submitted_at":"2025-01-01T00:00:00Z"}]' \
  "abc123sha" \
  "$LOG2"
PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO="owner/repo" PR_NUMBER=200 OWNER="owner" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -Fxq "ARG:conclusion=failure" "$LOG2"; then
  pass "CHANGES_REQUESTED review → conclusion=failure"
else
  fail "CHANGES_REQUESTED 時の conclusion が想定と異なる: $(tr '\n' '|' < "$LOG2" | head -c 500)"
fi
rm -f "$LOG2"

LOG3="$(mktemp)"
make_stub '[]' "abc123sha" "$LOG3"
PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO="owner/repo" PR_NUMBER=200 OWNER="owner" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -Fxq "ARG:conclusion=neutral" "$LOG3"; then
  pass "review 未投稿 → conclusion=neutral"
else
  fail "review 未投稿時の conclusion が想定と異なる: $(tr '\n' '|' < "$LOG3" | head -c 500)"
fi
if grep -F "output[title]=vibehawk: review 未投稿" "$LOG3" > /dev/null; then
  pass "review 未投稿時の title に「review 未投稿」が含まれる"
else
  fail "review 未投稿時の title が想定と異なる"
fi
rm -f "$LOG3"

LOG4="$(mktemp)"
make_stub '[
  {"user":{"login":"vibehawk-for-owner[bot]"},"state":"APPROVED","body":"OK","submitted_at":"2025-01-01T00:00:00Z"},
  {"user":{"login":"vibehawk-for-owner[bot]"},"state":"COMMENTED","body":"","submitted_at":"2025-01-01T01:00:00Z"}
]' "abc" "$LOG4"
PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO="owner/repo" PR_NUMBER=200 OWNER="owner" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -Fxq "ARG:conclusion=success" "$LOG4"; then
  pass "substantive filter: 後発の空 COMMENTED に引きずられず APPROVED→success を維持"
else
  fail "substantive filter が機能していない: $(tr '\n' '|' < "$LOG4" | head -c 500)"
fi
rm -f "$LOG4"

LOG5="$(mktemp)"
make_stub '[{"user":{"login":"other-bot[bot]"},"state":"APPROVED","body":"...","submitted_at":"2025-01-01T00:00:00Z"}]' \
  "abc" "$LOG5"
PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO="owner/repo" PR_NUMBER=200 OWNER="owner" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -Fxq "ARG:conclusion=neutral" "$LOG5"; then
  pass "別 bot の review は無視される → neutral（vibehawk-for-<owner>[bot] 名義のみ採用）"
else
  fail "別 bot review の扱いが想定と異なる: $(tr '\n' '|' < "$LOG5" | head -c 500)"
fi
rm -f "$LOG5"

LOG6="$(mktemp)"
make_stub '[{"user":{"login":"vibehawk-for-owner[bot]"},"state":"APPROVED","body":"OK","submitted_at":"2025-01-01T00:00:00Z"}]' \
  "headsha999" \
  "$LOG6"
PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO="owner/repo" PR_NUMBER=200 OWNER="owner" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -Fxq "ARG:name=vibehawk" "$LOG6" && \
   grep -Fxq "ARG:status=completed" "$LOG6" && \
   grep -Fxq "ARG:head_sha=headsha999" "$LOG6"; then
  pass "check-runs POST に name=vibehawk / status=completed / head_sha が渡る"
else
  fail "check-runs POST の固定フィールドが想定と異なる: $(tr '\n' '|' < "$LOG6" | head -c 500)"
fi
rm -f "$LOG6"

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
