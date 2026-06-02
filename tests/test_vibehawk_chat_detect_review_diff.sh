#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/detect-review-diff.sh の単体テスト（Issue #290、epic #289 子1）。
#
# 検証対象: `@vibehawk review` の差分有無判定。
#   - 前回レビュー sha（自 Bot review の <!-- vibehawk:sha=N --> マーカー）と HEAD_SHA を比較
#   - 初回 / sha 一致 / 新規コミット / マーカー無し / 不正 sha / 他ユーザー汚染 / gh 失敗 を網羅
# gh をスタブして reviews 一覧を制御する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/detect-review-diff.sh"

echo "=== scripts/ci/vibehawk-chat/detect-review-diff.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "detect-review-diff.sh が存在する"
else
  fail "detect-review-diff.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

# gh スタブ: REVIEWS_FIXTURE を返す。GH_FAIL=1 のとき非 0 終了（取得失敗の模擬）。
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${GH_FAIL:-}" == "1" ]]; then
  exit 1
fi
if [[ "${1:-}" == "api" ]]; then
  cat "$REVIEWS_FIXTURE"
  exit 0
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

HEAD="abc123abc123abc123abc123abc123abc123abcd"   # 40 桁 hex

# 自 Bot の summary review を組み立てる（sha と login を指定）
make_review() {
  # $1: sha（body の vibehawk:sha=）  $2: login  $3: summary マーカー有無（yes/no）
  local sha="$1" login="$2" marker="$3"
  local body
  if [[ "$marker" == "yes" ]]; then
    body="🦅 vibehawk\n\n<!-- vibehawk:summary -->\n<!-- vibehawk:sha=${sha} -->"
  else
    body="🦅 vibehawk（マーカー無し）"
  fi
  printf '[{"user":{"login":"%s"},"body":"%s","submitted_at":"2026-01-01T00:00:00Z"}]' "$login" "$body"
}

run_script() {
  # $1 reviews_json  $2 GH_FAIL(0/1)
  local reviews="$1" ghfail="${2:-0}"
  printf '%s' "$reviews" > "${TMP_DIR}/reviews.json"
  : > "${TMP_DIR}/github_output"
  local rc=0
  PATH="$STUB_DIR:$PATH" \
    REVIEWS_FIXTURE="${TMP_DIR}/reviews.json" \
    GH_FAIL="$ghfail" \
    GH_TOKEN=t REPO="hirokimry/vibehawk" PR_NUMBER=42 HEAD_SHA="$HEAD" OWNER="hirokimry" \
    GITHUB_OUTPUT="${TMP_DIR}/github_output" \
    bash "$SCRIPT" > "${TMP_DIR}/stdout" 2>&1 || rc=$?
  echo "$rc"
}

OUT="${TMP_DIR}/github_output"

echo "=== Case 1: 初回（reviews 空）→ diff_exists=true ==="
rc=$(run_script '[]' 0)
if [[ "$rc" -eq 0 ]] && grep -qx "diff_exists=true" "$OUT" && grep -qx "prev_sha=" "$OUT"; then
  pass "初回 → diff_exists=true / prev_sha 空"
else
  fail "Case1 不一致: rc=$rc out=$(cat "$OUT")"
fi

echo "=== Case 2: sha 一致（前回==HEAD）→ diff_exists=false ==="
rc=$(run_script "$(make_review "$HEAD" 'vibehawk-for-hirokimry[bot]' yes)" 0)
if [[ "$rc" -eq 0 ]] && grep -qx "diff_exists=false" "$OUT" && grep -qx "prev_sha=${HEAD}" "$OUT"; then
  pass "sha 一致 → diff_exists=false"
else
  fail "Case2 不一致: rc=$rc out=$(cat "$OUT")"
fi

echo "=== Case 3: 新規コミット（前回!=HEAD）→ diff_exists=true ==="
PREV="def456def456def456def456def456def456def4"
rc=$(run_script "$(make_review "$PREV" 'vibehawk-for-hirokimry[bot]' yes)" 0)
if [[ "$rc" -eq 0 ]] && grep -qx "diff_exists=true" "$OUT" && grep -qx "prev_sha=${PREV}" "$OUT"; then
  pass "新規コミット → diff_exists=true / prev_sha=前回"
else
  fail "Case3 不一致: rc=$rc out=$(cat "$OUT")"
fi

echo "=== Case 4: review はあるが summary マーカー無し → diff_exists=true ==="
rc=$(run_script "$(make_review "$HEAD" 'vibehawk-for-hirokimry[bot]' no)" 0)
if [[ "$rc" -eq 0 ]] && grep -qx "diff_exists=true" "$OUT" && grep -qx "prev_sha=" "$OUT"; then
  pass "マーカー無し → diff_exists=true / prev_sha 空"
else
  fail "Case4 不一致: rc=$rc out=$(cat "$OUT")"
fi

echo "=== Case 5: 不正 sha（41 桁・hex 超過）→ 初回扱い diff_exists=true ==="
BAD="abc123abc123abc123abc123abc123abc123abcde"   # 41 桁
rc=$(run_script "$(make_review "$BAD" 'vibehawk-for-hirokimry[bot]' yes)" 0)
if [[ "$rc" -eq 0 ]] && grep -qx "diff_exists=true" "$OUT" && grep -qx "prev_sha=" "$OUT"; then
  pass "不正 sha → 空扱い → diff_exists=true"
else
  fail "Case5 不一致: rc=$rc out=$(cat "$OUT")"
fi

echo "=== Case 6: 他ユーザー review に summary マーカー → bot フィルタで無視 → diff_exists=true ==="
rc=$(run_script "$(make_review "$HEAD" 'someuser' yes)" 0)
if [[ "$rc" -eq 0 ]] && grep -qx "diff_exists=true" "$OUT" && grep -qx "prev_sha=" "$OUT"; then
  pass "他ユーザーの summary マーカーは無視 → diff_exists=true"
else
  fail "Case6 不一致: rc=$rc out=$(cat "$OUT")"
fi

echo "=== Case 7: gh api 失敗 → 安全側 diff_exists=true ==="
rc=$(run_script '[]' 1)
if [[ "$rc" -eq 0 ]] && grep -qx "diff_exists=true" "$OUT" && grep -qx "prev_sha=" "$OUT"; then
  pass "gh 失敗 → 安全側 diff_exists=true"
else
  fail "Case7 不一致: rc=$rc out=$(cat "$OUT")"
fi

echo "=== Case 9: 大文字 OWNER でも bot login を小文字正規化して一致 → diff_exists=false ==="
# 実 bot login は小文字（vibehawk-for-hirokimry[bot]）だが OWNER は大文字混じりで渡る場合
printf '%s' "$(make_review "$HEAD" 'vibehawk-for-hirokimry[bot]' yes)" > "${TMP_DIR}/reviews.json"
: > "${TMP_DIR}/github_output"
rc=0
PATH="$STUB_DIR:$PATH" REVIEWS_FIXTURE="${TMP_DIR}/reviews.json" GH_FAIL=0 \
  GH_TOKEN=t REPO="HiroKimry/vibehawk" PR_NUMBER=42 HEAD_SHA="$HEAD" OWNER="HiroKimry" \
  GITHUB_OUTPUT="${TMP_DIR}/github_output" bash "$SCRIPT" > "${TMP_DIR}/stdout" 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -qx "diff_exists=false" "$OUT"; then
  pass "大文字 OWNER を正規化して bot login 一致 → diff_exists=false"
else
  fail "Case9 不一致: rc=$rc out=$(cat "$OUT")"
fi

echo "=== Case 8: 必須 env 未設定（HEAD_SHA 欠落）→ 非 0 終了 ==="
set +e
PATH="$STUB_DIR:$PATH" REVIEWS_FIXTURE="${TMP_DIR}/reviews.json" GH_FAIL=0 \
  GH_TOKEN=t REPO="hirokimry/vibehawk" PR_NUMBER=42 OWNER="hirokimry" \
  GITHUB_OUTPUT="${TMP_DIR}/github_output" bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then
  pass "HEAD_SHA 未設定で非 0 終了"
else
  fail "HEAD_SHA 未設定でも 0 終了してしまった"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
