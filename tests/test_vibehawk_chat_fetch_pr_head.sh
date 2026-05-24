#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/fetch-pr-head.sh 単体テスト（Issue #177）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/fetch-pr-head.sh"

PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/vibehawk-chat/fetch-pr-head.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "fetch-pr-head.sh が存在する"
else
  fail "fetch-pr-head.sh が存在しない"
  exit 1
fi

STUB_DIR="$(mktemp -d)"
GITHUB_OUTPUT_FILE="$(mktemp)"
LOG_FILE="$(mktemp)"
trap 'rm -rf "$STUB_DIR" "$GITHUB_OUTPUT_FILE" "$LOG_FILE"' EXIT

cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  printf '%s\n' "\$arg" >> "$LOG_FILE"
done
# --jq が含まれていれば SHA を返す（fetch-pr-head.sh は --jq '.head.sha' で呼ぶ）
all="\$*"
if [[ "\$all" == *"--jq"* ]]; then
  echo "abc123def456"
fi
EOF
chmod +x "$STUB_DIR/gh"

PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy \
  REPO="owner/repo" \
  PR_NUMBER=200 \
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
  bash "$SCRIPT" > /dev/null

if grep -F "repos/owner/repo/pulls/200" "$LOG_FILE" > /dev/null; then
  pass "gh api が repos/<owner>/<repo>/pulls/<PR_NUMBER> で呼ばれる"
else
  fail "gh api のエンドポイントが想定と異なる: $(tr '\n' '|' < "$LOG_FILE")"
fi

if grep -Fxq -- "--jq" "$LOG_FILE" && grep -Fxq ".head.sha" "$LOG_FILE"; then
  pass "--jq '.head.sha' が渡される"
else
  fail "--jq '.head.sha' が渡されない: $(tr '\n' '|' < "$LOG_FILE")"
fi

if grep -Fxq "head_sha=abc123def456" "$GITHUB_OUTPUT_FILE"; then
  pass "GITHUB_OUTPUT に head_sha=<sha> が書かれる"
else
  fail "GITHUB_OUTPUT に head_sha が書かれない: $(tr '\n' '|' < "$GITHUB_OUTPUT_FILE")"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
