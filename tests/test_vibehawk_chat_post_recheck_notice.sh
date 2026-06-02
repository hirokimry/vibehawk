#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/post-recheck-notice.sh の単体テスト（Issue #290、epic #289 子1）。
#
# 検証対象: 差分なし経路の通知コメント。
#   - DECIDED_EVENT（SKIP / APPROVE / REQUEST_CHANGES / 未知値）で文面分岐
#   - REQUEST_CHANGES 時に UNRESOLVED_COUNT の実値が文面へ埋め込まれる
#   - 本文に @vibehawk を含めない（無限ループ防止）
# gh をスタブして issue comment の投稿本文を記録する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/post-recheck-notice.sh"

echo "=== scripts/ci/vibehawk-chat/post-recheck-notice.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "post-recheck-notice.sh が存在する"
else
  fail "post-recheck-notice.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

# gh スタブ: issue comment の --body 値を BODY_LOG に記録する
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  shift 2
  # 残り引数から --body の値を取り出す
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--body" ]]; then
      printf '%s' "$2" > "$BODY_LOG"
      exit 0
    fi
    shift
  done
  exit 0
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

run_script() {
  # $1 DECIDED_EVENT  $2 UNRESOLVED_COUNT(任意)
  local ev="$1" cnt="${2:-}"
  : > "${TMP_DIR}/body.log"
  local rc=0
  PATH="$STUB_DIR:$PATH" \
    BODY_LOG="${TMP_DIR}/body.log" \
    GH_TOKEN=t ISSUE_NUMBER=42 DECIDED_EVENT="$ev" UNRESOLVED_COUNT="$cnt" \
    bash "$SCRIPT" > "${TMP_DIR}/stdout" 2>&1 || rc=$?
  echo "$rc"
}

BODY="${TMP_DIR}/body.log"

echo "=== Case 1: SKIP → 判定変更なし文面 ==="
rc=$(run_script SKIP "")
if [[ "$rc" -eq 0 ]] && grep -qF "再チェックのみ実施" "$BODY" && grep -qF "指摘が無いため" "$BODY"; then
  pass "SKIP → 判定変更なし文面"
else
  fail "Case1 不一致: rc=$rc body=$(cat "$BODY")"
fi

echo "=== Case 2: APPROVE → APPROVE 更新文面 ==="
rc=$(run_script APPROVE "")
if [[ "$rc" -eq 0 ]] && grep -qF "APPROVE" "$BODY" && grep -qF "解決済み" "$BODY"; then
  pass "APPROVE → APPROVE 更新文面"
else
  fail "Case2 不一致: rc=$rc body=$(cat "$BODY")"
fi

echo "=== Case 3: REQUEST_CHANGES → UNRESOLVED_COUNT の実値が埋め込まれる ==="
rc=$(run_script REQUEST_CHANGES 3)
if [[ "$rc" -eq 0 ]] && grep -qF "3 件" "$BODY" && grep -qF "CHANGES_REQUESTED" "$BODY"; then
  pass "REQUEST_CHANGES → 未解決 3 件が文面に埋め込まれる"
else
  fail "Case3 不一致: rc=$rc body=$(cat "$BODY")"
fi

echo "=== Case 4: 未知値 → 汎用文面でフォールバック ==="
rc=$(run_script WEIRD "")
if [[ "$rc" -eq 0 ]] && grep -qF "再チェックのみ実施" "$BODY"; then
  pass "未知値 → 汎用文面フォールバック"
else
  fail "Case4 不一致: rc=$rc body=$(cat "$BODY")"
fi

echo "=== Case 5: 全分岐で本文に @vibehawk を含まない（無限ループ防止） ==="
ng=0
for ev in SKIP APPROVE REQUEST_CHANGES WEIRD; do
  run_script "$ev" 1 > /dev/null
  if grep -qF "@vibehawk" "$BODY"; then
    ng=1
  fi
done
if [[ "$ng" -eq 0 ]]; then
  pass "全分岐で本文に @vibehawk を含まない"
else
  fail "本文に @vibehawk が含まれている（無限ループの危険）"
fi

echo "=== Case 6: 必須 env 未設定（DECIDED_EVENT 欠落）→ 非 0 終了 ==="
set +e
PATH="$STUB_DIR:$PATH" BODY_LOG="${TMP_DIR}/body.log" \
  GH_TOKEN=t ISSUE_NUMBER=42 bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then
  pass "DECIDED_EVENT 未設定で非 0 終了"
else
  fail "DECIDED_EVENT 未設定でも 0 終了してしまった"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
