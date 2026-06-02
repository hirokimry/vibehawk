#!/usr/bin/env bash
# scripts/ci/vibehawk-review/post-autoreview-paused-status.sh の単体テスト（Issue #295、epic #289 子6）。
#
# 検証対象: 自動レビュー paused / ignored 時に `vibehawk` status check を success「一時停止中」で post する。
#   - paused / ignored → conclusion=success + name=vibehawk で check-runs POST
#   - active 等 paused/ignored 以外 → POST せず skip
#   - env 欠落で非 0
# gh をスタブして check-runs POST 引数を記録する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/post-autoreview-paused-status.sh"
echo "=== scripts/ci/vibehawk-review/post-autoreview-paused-status.sh 単体テスト ==="
if [[ -f "$SCRIPT" ]]; then pass "存在する"; else fail "存在しない"; exit 1; fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT
STUB_DIR="${TMP_DIR}/stub"; mkdir -p "$STUB_DIR"

# gh スタブ: check-runs POST の全引数を POST_LOG に記録する
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "api" && "${2:-}" == "-X" && "${3:-}" == "POST" ]]; then
  printf '%s\n' "$@" >> "$POST_LOG"
  exit 0
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

run_script() {
  # $1 AUTOREVIEW_STATE
  : > "${TMP_DIR}/post.log"
  local rc=0
  PATH="$STUB_DIR:$PATH" POST_LOG="${TMP_DIR}/post.log" \
    GH_TOKEN=t REPO="hirokimry/vibehawk" HEAD_SHA="abc123" AUTOREVIEW_STATE="$1" \
    bash "$SCRIPT" > "${TMP_DIR}/stdout" 2>&1 || rc=$?
  echo "$rc"
}
POST="${TMP_DIR}/post.log"

echo "=== Case 1: paused → vibehawk=success check-run を POST ==="
rc=$(run_script paused)
if [[ "$rc" -eq 0 ]] && grep -qF "check-runs" "$POST" \
   && grep -qF "name=vibehawk" "$POST" \
   && grep -qF "conclusion=success" "$POST" \
   && grep -qF "head_sha=abc123" "$POST"; then
  pass "paused → name=vibehawk / conclusion=success / head_sha で POST"
else
  fail "Case1 不一致: rc=$rc post=$(cat "$POST")"
fi

echo "=== Case 2: ignored → vibehawk=success check-run を POST ==="
rc=$(run_script ignored)
if [[ "$rc" -eq 0 ]] && grep -qF "conclusion=success" "$POST" && grep -qF "name=vibehawk" "$POST"; then
  pass "ignored → conclusion=success で POST"
else
  fail "Case2 不一致: rc=$rc post=$(cat "$POST")"
fi

echo "=== Case 3: active（paused/ignored 以外）→ POST せず skip ==="
rc=$(run_script active)
if [[ "$rc" -eq 0 ]] && [[ ! -s "$POST" ]]; then
  pass "active → POST なし（skip）"
else
  fail "Case3 不一致: rc=$rc post=$(cat "$POST")"
fi

echo "=== Case 4: 必須 env 未設定（AUTOREVIEW_STATE 欠落）→ 非 0 終了 ==="
set +e
PATH="$STUB_DIR:$PATH" POST_LOG="${TMP_DIR}/post.log" \
  GH_TOKEN=t REPO="hirokimry/vibehawk" HEAD_SHA="abc123" bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then pass "AUTOREVIEW_STATE 未設定で非 0 終了"; else fail "AUTOREVIEW_STATE 未設定でも 0 終了"; fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
