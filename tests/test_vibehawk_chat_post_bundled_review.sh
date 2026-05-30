#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/post-bundled-review.sh 単体テスト（Issue #177）
#
# 検証対象:
#   - payload ファイル 2 件が揃っていれば bundled review POST が呼ばれる
#   - payload ファイルが片方欠落していれば exit 0 + ::warning:: でスキップ
#   - event が APPROVE / REQUEST_CHANGES 以外 → exit 1 + ::error::
#   - body が空 → exit 1 + ::error::

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/post-bundled-review.sh"

PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/vibehawk-chat/post-bundled-review.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "post-bundled-review.sh が存在する"
else
  fail "post-bundled-review.sh が存在しない"
  exit 1
fi

STUB_DIR="$(mktemp -d)"
LOG_FILE="$(mktemp)"
EVENT_FILE="/tmp/vibehawk-chat-review-event.txt"
BODY_FILE="/tmp/vibehawk-chat-review-body.txt"
trap 'rm -rf "$STUB_DIR" "$LOG_FILE" "$EVENT_FILE" "$BODY_FILE"' EXIT

# gh スタブ: gh api -X POST ... --input - を受けて stdin の JSON を LOG_FILE に書く
cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
# 引数を 1 行 1 引数で LOG_FILE に書く
for arg in "\$@"; do
  printf 'ARG:%s\n' "\$arg" >> "$LOG_FILE"
done
# --input - を受けたら stdin を LOG_FILE に書く
all="\$*"
if [[ "\$all" == *"--input"* ]]; then
  echo "STDIN:" >> "$LOG_FILE"
  cat >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"
fi
EOF
chmod +x "$STUB_DIR/gh"

rm -f "$EVENT_FILE" "$BODY_FILE" "$LOG_FILE"
printf 'APPROVE\n' > "$EVENT_FILE"
printf '🦅 vibehawk: 再レビュー本文\n<!-- vibehawk:summary -->\n<!-- vibehawk:sha=abc -->\n' > "$BODY_FILE"
touch "$LOG_FILE"
PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy \
  REPO="owner/repo" \
  PR_NUMBER=200 \
  HEAD_SHA="abc123" \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -F "ARG:repos/owner/repo/pulls/200/reviews" "$LOG_FILE" > /dev/null && \
   grep -F "ARG:--input" "$LOG_FILE" > /dev/null; then
  pass "payload 揃い時に gh api POST repos/<o>/<r>/pulls/<n>/reviews が呼ばれる"
else
  fail "POST 呼び出しが想定と異なる: $(tr '\n' '|' < "$LOG_FILE" | head -c 400)"
fi

# 1b: stdin の JSON に event / body / commit_id が入る
if grep -F '"event": "APPROVE"' "$LOG_FILE" > /dev/null && \
   grep -F '"commit_id": "abc123"' "$LOG_FILE" > /dev/null; then
  pass "POST stdin の JSON に event=APPROVE と commit_id=abc123 が含まれる"
else
  fail "POST stdin の JSON が想定と異なる: $(tr '\n' '|' < "$LOG_FILE" | head -c 400)"
fi

rm -f "$EVENT_FILE" "$BODY_FILE" "$LOG_FILE"
printf 'APPROVE\n' > "$EVENT_FILE"
touch "$LOG_FILE"
set +e
out2="$(PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO=o/r PR_NUMBER=1 HEAD_SHA=x \
  bash "$SCRIPT" 2>&1)"
code2=$?
set -e
if [[ $code2 -eq 0 ]] && echo "$out2" | grep -F "::warning::" > /dev/null && \
   echo "$out2" | grep -F "payload ファイル" > /dev/null; then
  pass "payload 片方欠落 → exit 0 + ::warning:: でスキップ"
else
  fail "payload 欠落時の挙動が想定と異なる: exit=$code2, out='$out2'"
fi

rm -f "$EVENT_FILE" "$BODY_FILE" "$LOG_FILE"
printf 'COMMENTED\n' > "$EVENT_FILE"
printf 'body text\n' > "$BODY_FILE"
touch "$LOG_FILE"
set +e
out3="$(PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO=o/r PR_NUMBER=1 HEAD_SHA=x \
  bash "$SCRIPT" 2>&1)"
code3=$?
set -e
if [[ $code3 -ne 0 ]] && echo "$out3" | grep -F "::error::" > /dev/null && \
   echo "$out3" | grep -F "不正な event 値" > /dev/null; then
  pass "不正 event (COMMENTED) → exit 非 0 + ::error:: 不正な event 値"
else
  fail "不正 event 時の挙動が想定と異なる: exit=$code3, out='$out3'"
fi

rm -f "$EVENT_FILE" "$BODY_FILE" "$LOG_FILE"
printf 'APPROVE\n' > "$EVENT_FILE"
printf ' ' > "$BODY_FILE"
touch "$LOG_FILE"
set +e
out4="$(PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO=o/r PR_NUMBER=1 HEAD_SHA=x \
  bash "$SCRIPT" 2>&1)"
code4=$?
set -e
if [[ $code4 -ne 0 ]] && echo "$out4" | grep -F "::error::" > /dev/null && \
   echo "$out4" | grep -F "REVIEW_BODY が空" > /dev/null; then
  pass "空 body → exit 非 0 + ::error:: REVIEW_BODY が空"
else
  fail "空 body 時の挙動が想定と異なる: exit=$code4, out='$out4'"
fi

rm -f "$EVENT_FILE" "$BODY_FILE" "$LOG_FILE"
printf '  REQUEST_CHANGES  \n\n' > "$EVENT_FILE"
printf 'body\n' > "$BODY_FILE"
touch "$LOG_FILE"
PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy REPO=o/r PR_NUMBER=1 HEAD_SHA=x \
  bash "$SCRIPT" > /dev/null 2>&1
if grep -F '"event": "REQUEST_CHANGES"' "$LOG_FILE" > /dev/null; then
  pass "余分な空白/改行付き event が REQUEST_CHANGES に正規化される"
else
  fail "event 正規化が想定と異なる: $(tr '\n' '|' < "$LOG_FILE" | head -c 400)"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
