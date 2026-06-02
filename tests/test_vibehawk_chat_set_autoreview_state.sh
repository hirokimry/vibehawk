#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/set-autoreview-state.sh の単体テスト（Issue #295、epic #289 子6）。
#   - pause→paused / resume→active / ignore→ignored のマーカー upsert
#   - 既存マーカーありで PATCH / 無しで POST
#   - 確認コメント本文に @vibehawk コマンドを含めない（無限ループ防止、CISO 要件 2）
#   - env 欠落で非 0

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/set-autoreview-state.sh"
echo "=== set-autoreview-state.sh 単体テスト ==="
if [[ -f "$SCRIPT" ]]; then pass "存在する"; else fail "存在しない"; exit 1; fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT
STUB_DIR="${TMP_DIR}/stub"; mkdir -p "$STUB_DIR"

# gh スタブ: issues/comments GET は COMMENTS_FIXTURE、POST/PATCH は METHOD_LOG に method + body 記録
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "api" && "${2:-}" == "-X" ]]; then
  method="${3:-}"
  printf 'METHOD=%s\n' "$method" >> "$METHOD_LOG"
  cat >> "$METHOD_LOG"
  printf '{"id":1}'
  exit 0
fi
if [[ "${1:-}" == "api" ]]; then
  cat "$COMMENTS_FIXTURE"
  exit 0
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

run_script() {
  # $1 COMMENT_BODY  $2 comments fixture json
  printf '%s' "$2" > "${TMP_DIR}/comments.json"
  : > "${TMP_DIR}/method.log"
  local rc=0
  PATH="$STUB_DIR:$PATH" COMMENTS_FIXTURE="${TMP_DIR}/comments.json" METHOD_LOG="${TMP_DIR}/method.log" \
    GH_TOKEN=t REPO="hirokimry/vibehawk" ISSUE_NUMBER=42 OWNER="hirokimry" COMMENT_BODY="$1" \
    bash "$SCRIPT" > "${TMP_DIR}/stdout" 2>&1 || rc=$?
  echo "$rc"
}
LOG="${TMP_DIR}/method.log"

echo "=== Case 1: pause → paused マーカーを新規 POST ==="
rc=$(run_script "@vibehawk pause" "[]")
if [[ "$rc" -eq 0 ]] && grep -qF "METHOD=POST" "$LOG" && grep -qF "vibehawk:autoreview=paused" "$LOG"; then
  pass "pause → paused マーカーを POST"
else
  fail "Case1: rc=$rc log=$(cat "$LOG")"
fi

echo "=== Case 2: resume → active（既存マーカーありで PATCH） ==="
existing='[{"user":{"login":"vibehawk-for-hirokimry[bot]"},"body":"x <!-- vibehawk:autoreview=paused -->","created_at":"2026-01-01T00:00:00Z","id":99}]'
rc=$(run_script "@vibehawk resume" "$existing")
if [[ "$rc" -eq 0 ]] && grep -qF "METHOD=PATCH" "$LOG" && grep -qF "vibehawk:autoreview=active" "$LOG"; then
  pass "resume → active マーカーを既存 PATCH"
else
  fail "Case2: rc=$rc log=$(cat "$LOG")"
fi

echo "=== Case 3: ignore → ignored マーカー ==="
rc=$(run_script "@vibehawk ignore" "[]")
if [[ "$rc" -eq 0 ]] && grep -qF "vibehawk:autoreview=ignored" "$LOG"; then
  pass "ignore → ignored マーカー"
else
  fail "Case3: rc=$rc log=$(cat "$LOG")"
fi

echo "=== Case 4: 確認本文の @vibehawk は全てバッククォート例示（裸出現なし、CISO 要件2） ==="
# CISO 要件2: 確認コメントにコマンドの裸出現を含めない（バッククォート例示のみ許容）。
# 本文の各 @vibehawk 出現が直前バッククォート（`@vibehawk）であることを確認する。
run_script "@vibehawk pause" "[]" > /dev/null
body_only="$(grep -v '^METHOD=' "$LOG")"
at_count="$(printf '%s' "$body_only" | grep -oF '@vibehawk' | grep -c . || true)"
fenced_count="$(printf '%s' "$body_only" | grep -oF '`@vibehawk' | grep -c . || true)"
if [[ "$at_count" -eq "$fenced_count" ]]; then
  pass "確認本文の @vibehawk は全てバッククォート例示（${fenced_count}/${at_count}、裸出現なし）"
else
  fail "確認本文に裸の @vibehawk コマンドがある（${fenced_count}/${at_count}、無限ループ危険）"
fi

echo "=== Case 5: env 欠落（COMMENT_BODY）→ 非 0 ==="
set +e
PATH="$STUB_DIR:$PATH" COMMENTS_FIXTURE="${TMP_DIR}/comments.json" METHOD_LOG="${TMP_DIR}/method.log" \
  GH_TOKEN=t REPO="hirokimry/vibehawk" ISSUE_NUMBER=42 OWNER="hirokimry" bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then pass "COMMENT_BODY 未設定で非 0"; else fail "COMMENT_BODY 未設定でも 0 終了"; fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
