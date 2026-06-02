#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/post-help.sh の単体テスト（Issue #294、epic #289 子5）。
#   - コマンド一覧 9 種を全て含む / 外部 URL を含まない / env 欠落で非 0

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/post-help.sh"
echo "=== scripts/ci/vibehawk-chat/post-help.sh 単体テスト ==="
if [[ -f "$SCRIPT" ]]; then pass "post-help.sh が存在する"; else fail "post-help.sh が存在しない"; exit 1; fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT
STUB_DIR="${TMP_DIR}/stub"; mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  shift 2
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--body" ]]; then printf '%s' "$2" > "$BODY_LOG"; exit 0; fi
    shift
  done
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

BODY="${TMP_DIR}/body.log"
: > "$BODY"
rc=0
PATH="$STUB_DIR:$PATH" BODY_LOG="$BODY" GH_TOKEN=t ISSUE_NUMBER=42 bash "$SCRIPT" >/dev/null 2>&1 || rc=$?

echo "=== Case 1: コマンド一覧 9 種を全て含む ==="
miss=0
for cmd in "@vibehawk review" "@vibehawk full review" "@vibehawk resolve" "@vibehawk summary" "@vibehawk help" "@vibehawk configuration" "@vibehawk pause" "@vibehawk resume" "@vibehawk ignore"; do
  grep -qF "$cmd" "$BODY" || { echo "    欠落: $cmd"; miss=1; }
done
if [[ "$rc" -eq 0 ]] && [[ "$miss" -eq 0 ]]; then
  pass "9 コマンドすべてが help 本文に含まれる"
else
  fail "Case1 不一致: rc=$rc body=$(head -c 300 "$BODY")"
fi

echo "=== Case 2: 外部 URL を含まない（http:// / https://） ==="
if ! grep -qE 'https?://' "$BODY"; then
  pass "help 本文に外部 URL を含まない"
else
  fail "help 本文に外部 URL が含まれる"
fi

echo "=== Case 3: 必須 env 未設定（ISSUE_NUMBER 欠落）→ 非 0 終了 ==="
set +e
PATH="$STUB_DIR:$PATH" BODY_LOG="$BODY" GH_TOKEN=t bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then pass "ISSUE_NUMBER 未設定で非 0 終了"; else fail "ISSUE_NUMBER 未設定でも 0 終了"; fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
