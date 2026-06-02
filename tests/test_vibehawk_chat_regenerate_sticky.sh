#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/regenerate-sticky.sh の統合テスト（Issue #293、epic #289 子4）。
#
# 検証対象: @vibehawk summary の LLM 非依存 sticky 再生成。
#   - 既存 vibehawk インライン指摘から severity 集計が sticky に復元される
#   - 自 Bot 以外のインラインは除外される
#   - 直近 review state から DECIDED_EVENT を導出して verdict を保持する
#   - インライン 0 件でも sticky を upsert する
#   - env 欠落で非 0
# regenerate-sticky.sh は実 build-sticky-body.sh / post-sticky-comment.sh を呼ぶため統合テスト。
# gh をスタブして pulls/comments・commits・files・reviews・issues/comments（upsert）を分岐する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/regenerate-sticky.sh"

echo "=== scripts/ci/vibehawk-chat/regenerate-sticky.sh 統合テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "regenerate-sticky.sh が存在する"
else
  fail "regenerate-sticky.sh が存在しない"
  exit 1
fi

# 流用先スクリプトの存在確認（相対パス到達）
for dep in build-sticky-body.sh post-sticky-comment.sh; do
  if [[ -f "${REPO_ROOT}/scripts/ci/vibehawk-review/${dep}" ]]; then
    pass "流用先 scripts/ci/vibehawk-review/${dep} が存在する"
  else
    fail "流用先 ${dep} が存在しない"
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

# gh スタブ: endpoint で分岐し fixture を返す。upsert（POST/PATCH issues comments）は UPSERT_LOG に body 記録。
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "api" && ( "${2:-}" == "-X" ) ]]; then
  # upsert（POST/PATCH）: --input - で stdin から body JSON を受ける
  cat > "$UPSERT_LOG"
  printf '{"html_url":"https://github.com/x/y/issues/1#stub"}'
  exit 0
fi
if [[ "${1:-}" == "api" ]]; then
  ep="${2:-}"
  case "$ep" in
    *"/pulls/"*"/comments") cat "$INLINE_FIXTURE";;
    *"/pulls/"*"/commits")  cat "$COMMITS_FIXTURE";;
    *"/pulls/"*"/files")    cat "$FILES_FIXTURE";;
    *"/pulls/"*"/reviews")  cat "$REVIEWS_FIXTURE";;
    *"/issues/"*"/comments") cat "$ISSUE_COMMENTS_FIXTURE";;
    *) printf '[]';;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

run_script() {
  : > "${TMP_DIR}/upsert.log"
  local rc=0
  PATH="$STUB_DIR:$PATH" \
    INLINE_FIXTURE="${TMP_DIR}/inline.json" \
    COMMITS_FIXTURE="${TMP_DIR}/commits.json" \
    FILES_FIXTURE="${TMP_DIR}/files.json" \
    REVIEWS_FIXTURE="${TMP_DIR}/reviews.json" \
    ISSUE_COMMENTS_FIXTURE="${TMP_DIR}/issue_comments.json" \
    UPSERT_LOG="${TMP_DIR}/upsert.log" \
    GH_TOKEN=t REPO="hirokimry/vibehawk" PR_NUMBER=42 HEAD_SHA="abc123" OWNER="hirokimry" \
    bash "$SCRIPT" > "${TMP_DIR}/stdout" 2>&1 || rc=$?
  echo "$rc"
}

# デフォルト fixtures
printf '[]' > "${TMP_DIR}/commits.json"
printf '[]' > "${TMP_DIR}/files.json"
printf '[]' > "${TMP_DIR}/issue_comments.json"

UP="${TMP_DIR}/upsert.log"

echo "=== Case 1: 自 Bot インライン 🔴×1 🟡×1 + 他者 1 件 → severity 集計に own のみ復元 ==="
cat > "${TMP_DIR}/inline.json" <<'EOF'
[{"user":{"login":"vibehawk-for-hirokimry[bot]"},"path":"a.sh","line":10,"body":"🔴 Critical: x"},
 {"user":{"login":"vibehawk-for-hirokimry[bot]"},"path":"b.sh","line":20,"body":"🟡 Minor: y"},
 {"user":{"login":"someuser"},"path":"c.sh","line":30,"body":"🔴 Critical: 他者"}]
EOF
printf '[]' > "${TMP_DIR}/reviews.json"
rc=$(run_script)
body="$(jq -r '.body' "$UP" 2>/dev/null || cat "$UP")"
# severity 集計テーブル: critical=1 major=0 minor=1 が含まれる（他者の critical は除外で critical=1）
if [[ "$rc" -eq 0 ]] && printf '%s' "$body" | grep -F "vibehawk:sticky" >/dev/null \
   && printf '%s' "$body" | grep -F "| 1 | 0 | 1 | 0 | 0 |" >/dev/null; then
  pass "自 Bot インラインのみ severity 集計（critical=1 minor=1、他者除外）して sticky upsert"
else
  fail "Case1 不一致: rc=$rc body=$(printf '%s' "$body" | head -c 400)"
fi

echo "=== Case 2: 直近 review が CHANGES_REQUESTED → DECIDED_EVENT=REQUEST_CHANGES が sticky state に保持 ==="
cat > "${TMP_DIR}/reviews.json" <<'EOF'
[{"user":{"login":"vibehawk-for-hirokimry[bot]"},"state":"CHANGES_REQUESTED","body":"x","submitted_at":"2026-01-01T00:00:00Z"}]
EOF
rc=$(run_script)
body="$(jq -r '.body' "$UP" 2>/dev/null || cat "$UP")"
if [[ "$rc" -eq 0 ]] && printf '%s' "$body" | grep -F "REQUEST_CHANGES" >/dev/null; then
  pass "直近 CHANGES_REQUESTED → DECIDED_EVENT=REQUEST_CHANGES を sticky に保持"
else
  fail "Case2 不一致: rc=$rc body=$(printf '%s' "$body" | head -c 400)"
fi

echo "=== Case 3: インライン 0 件でも sticky を upsert（severity 0/0/0/0/0） ==="
printf '[]' > "${TMP_DIR}/inline.json"
printf '[]' > "${TMP_DIR}/reviews.json"
rc=$(run_script)
body="$(jq -r '.body' "$UP" 2>/dev/null || cat "$UP")"
if [[ "$rc" -eq 0 ]] && printf '%s' "$body" | grep -F "vibehawk:sticky" >/dev/null \
   && printf '%s' "$body" | grep -F "| 0 | 0 | 0 | 0 | 0 |" >/dev/null; then
  pass "インライン 0 件でも sticky を upsert（severity 全 0）"
else
  fail "Case3 不一致: rc=$rc body=$(printf '%s' "$body" | head -c 400)"
fi

echo "=== Case 4: 必須 env 未設定（HEAD_SHA 欠落）→ 非 0 終了 ==="
set +e
PATH="$STUB_DIR:$PATH" INLINE_FIXTURE="${TMP_DIR}/inline.json" COMMITS_FIXTURE="${TMP_DIR}/commits.json" \
  FILES_FIXTURE="${TMP_DIR}/files.json" REVIEWS_FIXTURE="${TMP_DIR}/reviews.json" \
  ISSUE_COMMENTS_FIXTURE="${TMP_DIR}/issue_comments.json" UPSERT_LOG="${TMP_DIR}/upsert.log" \
  GH_TOKEN=t REPO="hirokimry/vibehawk" PR_NUMBER=42 OWNER="hirokimry" bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then
  pass "HEAD_SHA 未設定で非 0 終了"
else
  fail "HEAD_SHA 未設定でも 0 終了してしまった"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
