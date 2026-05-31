#!/usr/bin/env bash
# scripts/ci/vibehawk-review/re-evaluate-verdict.sh の単体テスト（Issue #287）。
#
# 検証対象: pull_request_review_thread イベントでの verdict 再評価軽量パス。
#   - vibehawk 自身スレッドの未解決件数のみで APPROVE / REQUEST_CHANGES を決める
#   - 自 Bot スレッドが 0 件なら skip（管轄外）
#   - 直近 review state と一致なら POST skip（冪等）
# gh をスタブして graphql（スレッド+author）/ reviews 一覧 / reviews POST を制御する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/re-evaluate-verdict.sh"

echo "=== scripts/ci/vibehawk-review/re-evaluate-verdict.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "re-evaluate-verdict.sh が存在する"
else
  fail "re-evaluate-verdict.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

# gh スタブ: THREADS_FIXTURE / REVIEWS_FIXTURE を返し、POST 引数を POST_LOG に記録する。
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "api" && "${2:-}" == "graphql" ]]; then
  cat "$THREADS_FIXTURE"
  exit 0
fi
if [[ "${1:-}" == "api" && "${2:-}" == "-X" && "${3:-}" == "POST" ]]; then
  printf '%s\n' "$@" >> "$POST_LOG"
  exit 0
fi
if [[ "${1:-}" == "api" ]]; then
  cat "$REVIEWS_FIXTURE"
  exit 0
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

HEAD="headsha"

# THREADS_JSON ビルダー: vibehawk スレッド（resolved 真偽の配列）+ 人間スレッド数を組み立てる
make_threads() {
  # $1: vibehawk スレッドの isResolved を空白区切りで（例 "true true" / "false"）。空なら 0 件
  # $2: 人間スレッド数
  local own="$1" human="$2"
  {
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":['
    local first=1 r
    for r in $own; do
      [[ $first -eq 0 ]] && printf ','
      printf '{"isResolved":%s,"comments":{"nodes":[{"author":{"login":"vibehawk-for-hirokimry"}}]}}' "$r"
      first=0
    done
    local i
    for ((i=0;i<human;i++)); do
      [[ $first -eq 0 ]] && printf ','
      printf '{"isResolved":false,"comments":{"nodes":[{"author":{"login":"someuser"}}]}}'
      first=0
    done
    printf ']}}}}}'
  }
}

# REVIEWS_JSON: 直近 vibehawk review の state を表す配列（1 ページ）
make_reviews() {
  # $1: state（APPROVED / CHANGES_REQUESTED）または空（review 無し）
  local state="$1"
  if [[ -z "$state" ]]; then
    printf '[]'
  else
    printf '[{"user":{"login":"vibehawk-for-hirokimry[bot]"},"commit_id":"%s","state":"%s","body":"x","submitted_at":"2026-01-01T00:00:00Z"}]' "$HEAD" "$state"
  fi
}

run_script() {
  # $1 threads_json  $2 reviews_json
  local threads="$1" reviews="$2"
  printf '%s' "$threads" > "${TMP_DIR}/threads.json"
  printf '%s' "$reviews" > "${TMP_DIR}/reviews.json"
  : > "${TMP_DIR}/post.log"
  : > "${TMP_DIR}/github_output"
  local rc=0
  PATH="$STUB_DIR:$PATH" \
    THREADS_FIXTURE="${TMP_DIR}/threads.json" \
    REVIEWS_FIXTURE="${TMP_DIR}/reviews.json" \
    POST_LOG="${TMP_DIR}/post.log" \
    GH_TOKEN=t REPO="hirokimry/vibehawk" PR_NUMBER=42 HEAD_SHA="$HEAD" OWNER="hirokimry" \
    GITHUB_OUTPUT="${TMP_DIR}/github_output" \
    bash "$SCRIPT" > "${TMP_DIR}/stdout" 2>&1 || rc=$?
  echo "$rc"
}

OUT="${TMP_DIR}/github_output"
POST="${TMP_DIR}/post.log"

echo "=== Case 1: 自 Bot 全 resolved + 直近 CHANGES_REQUESTED → APPROVE を POST ==="
rc=$(run_script "$(make_threads 'true true' 0)" "$(make_reviews CHANGES_REQUESTED)")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=APPROVE" "$OUT" \
   && grep -qx "unresolved_count=0" "$OUT" \
   && grep -q "event=APPROVE" "$POST" \
   && grep -q "commit_id=${HEAD}" "$POST" \
   && grep -q "body=" "$POST"; then
  pass "全 resolved → APPROVE review を非空 body + commit_id=HEAD で POST"
else
  fail "Case1 不一致: rc=$rc out=$(cat "$OUT") post=$(cat "$POST")"
fi

echo "=== Case 2: 自 Bot 未解決 1 件 + 直近 APPROVED → REQUEST_CHANGES を POST ==="
rc=$(run_script "$(make_threads 'false true' 0)" "$(make_reviews APPROVED)")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=REQUEST_CHANGES" "$OUT" \
   && grep -qx "unresolved_count=1" "$OUT" \
   && grep -q "event=REQUEST_CHANGES" "$POST"; then
  pass "未解決 1 件 → REQUEST_CHANGES を POST"
else
  fail "Case2 不一致: rc=$rc out=$(cat "$OUT") post=$(cat "$POST")"
fi

echo "=== Case 3: 自 Bot スレッド 0 件（人間スレッドのみ）→ skip ==="
rc=$(run_script "$(make_threads '' 2)" "$(make_reviews CHANGES_REQUESTED)")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=SKIP" "$OUT" \
   && [[ ! -s "$POST" ]]; then
  pass "自 Bot スレッド 0 件 → SKIP（POST 無し）"
else
  fail "Case3 不一致: rc=$rc out=$(cat "$OUT") post=$(cat "$POST")"
fi

echo "=== Case 4: 全 resolved + 直近すでに APPROVED → 冪等で POST skip ==="
rc=$(run_script "$(make_threads 'true' 0)" "$(make_reviews APPROVED)")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=APPROVE" "$OUT" \
   && [[ ! -s "$POST" ]]; then
  pass "直近 APPROVED と一致 → POST skip（冪等）"
else
  fail "Case4 不一致: rc=$rc out=$(cat "$OUT") post=$(cat "$POST")"
fi

echo "=== Case 5: 必須 env 未設定（HEAD_SHA 欠落）→ 非 0 終了 ==="
set +e
PATH="$STUB_DIR:$PATH" THREADS_FIXTURE="${TMP_DIR}/threads.json" REVIEWS_FIXTURE="${TMP_DIR}/reviews.json" \
  POST_LOG="${TMP_DIR}/post.log" GH_TOKEN=t REPO="hirokimry/vibehawk" PR_NUMBER=42 OWNER="hirokimry" \
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
