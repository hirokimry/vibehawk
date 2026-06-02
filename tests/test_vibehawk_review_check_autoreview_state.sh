#!/usr/bin/env bash
# scripts/ci/vibehawk-review/check-autoreview-state.sh の単体テスト（Issue #295、epic #289 子6）。
#   - 自 Bot マーカーから state 抽出（active/paused/ignored）
#   - マーカー不在で active / 取得失敗で active / 不正値で active（安全側）
#   - 外部者（非 vibehawk-for-）の偽マーカーを無視（CISO 要件1: 作者フィルタ）
#   - env 欠落で非 0

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/check-autoreview-state.sh"
echo "=== check-autoreview-state.sh 単体テスト ==="
if [[ -f "$SCRIPT" ]]; then pass "存在する"; else fail "存在しない"; exit 1; fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT
STUB_DIR="${TMP_DIR}/stub"; mkdir -p "$STUB_DIR"

cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${GH_FAIL:-}" == "1" ]]; then exit 1; fi
if [[ "${1:-}" == "api" ]]; then cat "$COMMENTS_FIXTURE"; exit 0; fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

run_script() {
  # $1 comments json  $2 GH_FAIL
  printf '%s' "$1" > "${TMP_DIR}/comments.json"
  : > "${TMP_DIR}/github_output"
  local rc=0
  PATH="$STUB_DIR:$PATH" COMMENTS_FIXTURE="${TMP_DIR}/comments.json" GH_FAIL="${2:-0}" \
    GH_TOKEN=t REPO="hirokimry/vibehawk" PR_NUMBER=42 OWNER="hirokimry" \
    GITHUB_OUTPUT="${TMP_DIR}/github_output" bash "$SCRIPT" > "${TMP_DIR}/stdout" 2>&1 || rc=$?
  echo "$rc"
}
OUT="${TMP_DIR}/github_output"
bot='vibehawk-for-hirokimry[bot]'

echo "=== Case 1: 自 Bot paused マーカー → state=paused ==="
rc=$(run_script "[{\"user\":{\"login\":\"$bot\"},\"body\":\"x <!-- vibehawk:autoreview=paused -->\",\"created_at\":\"2026-01-01T00:00:00Z\"}]")
if [[ "$rc" -eq 0 ]] && grep -qx "state=paused" "$OUT"; then pass "paused 抽出"; else fail "Case1: rc=$rc out=$(cat "$OUT")"; fi

echo "=== Case 2: マーカー不在 → state=active ==="
rc=$(run_script '[{"user":{"login":"someuser"},"body":"hello","created_at":"2026-01-01T00:00:00Z"}]')
if [[ "$rc" -eq 0 ]] && grep -qx "state=active" "$OUT"; then pass "マーカー不在 → active"; else fail "Case2: rc=$rc out=$(cat "$OUT")"; fi

echo "=== Case 3: 外部者の偽 ignored マーカー → 無視して active（作者フィルタ、CISO 要件1） ==="
rc=$(run_script '[{"user":{"login":"attacker"},"body":"fake <!-- vibehawk:autoreview=ignored -->","created_at":"2026-01-01T00:00:00Z"}]')
if [[ "$rc" -eq 0 ]] && grep -qx "state=active" "$OUT"; then pass "外部者の偽マーカーを無視 → active"; else fail "Case3: rc=$rc out=$(cat "$OUT")"; fi

echo "=== Case 4: 不正値マーカー → active（安全側） ==="
rc=$(run_script "[{\"user\":{\"login\":\"$bot\"},\"body\":\"<!-- vibehawk:autoreview=bogus -->\",\"created_at\":\"2026-01-01T00:00:00Z\"}]")
if [[ "$rc" -eq 0 ]] && grep -qx "state=active" "$OUT"; then pass "不正値 → active（安全側）"; else fail "Case4: rc=$rc out=$(cat "$OUT")"; fi

echo "=== Case 4b: 自 Bot ignored マーカー → state=ignored（ignore 正常系、Issue #295） ==="
rc=$(run_script "[{\"user\":{\"login\":\"$bot\"},\"body\":\"🚫 <!-- vibehawk:autoreview=ignored -->\",\"created_at\":\"2026-01-01T00:00:00Z\"}]")
if [[ "$rc" -eq 0 ]] && grep -qx "state=ignored" "$OUT"; then pass "自 Bot ignored マーカー → ignored（ignore 要件の正常系）"; else fail "Case4b: rc=$rc out=$(cat "$OUT")"; fi

echo "=== Case 5: 最新マーカー優先（paused→active の順で active） ==="
rc=$(run_script "[{\"user\":{\"login\":\"$bot\"},\"body\":\"<!-- vibehawk:autoreview=paused -->\",\"created_at\":\"2026-01-01T00:00:00Z\"},{\"user\":{\"login\":\"$bot\"},\"body\":\"<!-- vibehawk:autoreview=active -->\",\"created_at\":\"2026-01-02T00:00:00Z\"}]")
if [[ "$rc" -eq 0 ]] && grep -qx "state=active" "$OUT"; then pass "最新マーカー（active）を優先"; else fail "Case5: rc=$rc out=$(cat "$OUT")"; fi

echo "=== Case 6: gh 取得失敗 → active（安全側） ==="
rc=$(run_script '[]' 1)
if [[ "$rc" -eq 0 ]] && grep -qx "state=active" "$OUT"; then pass "取得失敗 → active"; else fail "Case6: rc=$rc out=$(cat "$OUT")"; fi

echo "=== Case 7: env 欠落（PR_NUMBER）→ 非 0 ==="
set +e
PATH="$STUB_DIR:$PATH" COMMENTS_FIXTURE="${TMP_DIR}/comments.json" GH_TOKEN=t REPO="hirokimry/vibehawk" \
  OWNER="hirokimry" GITHUB_OUTPUT="${TMP_DIR}/github_output" bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then pass "PR_NUMBER 未設定で非 0"; else fail "PR_NUMBER 未設定でも 0 終了"; fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
