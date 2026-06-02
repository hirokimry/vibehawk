#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/resolve-own-threads.sh の単体テスト（Issue #292、epic #289 子3）。
#
# 検証対象: @vibehawk resolve の手動一括 resolve。
#   - 自 Bot かつ未解決のスレッドのみ resolveReviewThread mutation する
#   - 他者・他 Bot スレッド / 既 resolved スレッドは対象にしない（二重防御）
#   - 不正 node_id を glob で弾く
#   - resolved_count 出力 / 確認コメント（@vibehawk 不含有）
#   - 対象 0 件 / env 欠落
# gh をスタブして graphql query（threads）/ graphql mutation / issue comment を分岐記録する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/resolve-own-threads.sh"

echo "=== scripts/ci/vibehawk-chat/resolve-own-threads.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "resolve-own-threads.sh が存在する"
else
  fail "resolve-own-threads.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

# gh スタブ:
#   - api graphql で query='...reviewThreads...' を含む → THREADS_FIXTURE を返す
#   - api graphql で mutation（resolveReviewThread）→ MUTATION_LOG に threadId を記録
#   - issue comment → COMMENT_LOG に --body を記録
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "api" && "${2:-}" == "graphql" ]]; then
  # 引数全体に resolveReviewThread が含まれれば mutation
  if printf '%s ' "$@" | grep -q 'resolveReviewThread'; then
    # -F id=<tid> から tid を抽出して記録
    for a in "$@"; do
      case "$a" in id=*) printf '%s\n' "${a#id=}" >> "$MUTATION_LOG";; esac
    done
    printf '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}'
    exit 0
  fi
  cat "$THREADS_FIXTURE"
  exit 0
fi
if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  shift 2
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--body" ]]; then printf '%s' "$2" > "$COMMENT_LOG"; exit 0; fi
    shift
  done
  exit 0
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

# reviewThreads JSON ビルダー。各引数は "id:resolved:login" 形式。
make_threads() {
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":['
  local first=1 spec id res login
  for spec in "$@"; do
    IFS=':' read -r id res login <<< "$spec"
    [[ $first -eq 0 ]] && printf ','
    printf '{"id":"%s","isResolved":%s,"comments":{"nodes":[{"author":{"login":"%s"}}]}}' "$id" "$res" "$login"
    first=0
  done
  printf ']}}}}}'
}

run_script() {
  printf '%s' "$1" > "${TMP_DIR}/threads.json"
  : > "${TMP_DIR}/mutation.log"
  : > "${TMP_DIR}/comment.log"
  : > "${TMP_DIR}/github_output"
  local rc=0
  PATH="$STUB_DIR:$PATH" \
    THREADS_FIXTURE="${TMP_DIR}/threads.json" \
    MUTATION_LOG="${TMP_DIR}/mutation.log" \
    COMMENT_LOG="${TMP_DIR}/comment.log" \
    GH_TOKEN=t REPO="hirokimry/vibehawk" PR_NUMBER=42 OWNER="hirokimry" ISSUE_NUMBER=42 \
    GITHUB_OUTPUT="${TMP_DIR}/github_output" \
    bash "$SCRIPT" > "${TMP_DIR}/stdout" 2>&1 || rc=$?
  echo "$rc"
}

MUT="${TMP_DIR}/mutation.log"
OUT="${TMP_DIR}/github_output"
CMT="${TMP_DIR}/comment.log"

echo "=== Case 1: 自 Bot 未解決 2 件 + 自 Bot 既解決 1 件 + 他者未解決 1 件 → 未解決 own 2 件のみ resolve ==="
threads="$(make_threads \
  'PRRT_own1:false:vibehawk-for-hirokimry' \
  'PRRT_own2:false:vibehawk-for-hirokimry' \
  'PRRT_owndone:true:vibehawk-for-hirokimry' \
  'PRRT_human:false:someuser')"
rc=$(run_script "$threads")
mut_count=$(grep -c . "$MUT" || true)
if [[ "$rc" -eq 0 ]] && [[ "$mut_count" -eq 2 ]] \
   && grep -qx "PRRT_own1" "$MUT" && grep -qx "PRRT_own2" "$MUT" \
   && ! grep -qx "PRRT_owndone" "$MUT" && ! grep -qx "PRRT_human" "$MUT" \
   && grep -qx "resolved_count=2" "$OUT"; then
  pass "自 Bot 未解決 2 件のみ resolve（既解決・他者は対象外）、resolved_count=2"
else
  fail "Case1 不一致: rc=$rc mut=[$(cat "$MUT" | tr '\n' ',')] out=$(cat "$OUT")"
fi

echo "=== Case 2: 確認コメントが投稿され @vibehawk を含まない ==="
if grep -qF "2 件を resolve" "$CMT" && ! grep -qF "@vibehawk" "$CMT"; then
  pass "確認コメント（N 件 resolve）投稿、@vibehawk 不含有"
else
  fail "Case2 不一致: comment=$(cat "$CMT")"
fi

echo "=== Case 3: 対象 0 件（自 Bot 未解決なし）→ mutation なし・解決対象なしコメント ==="
threads="$(make_threads 'PRRT_done:true:vibehawk-for-hirokimry' 'PRRT_h:false:someuser')"
rc=$(run_script "$threads")
if [[ "$rc" -eq 0 ]] && [[ ! -s "$MUT" ]] \
   && grep -qx "resolved_count=0" "$OUT" \
   && grep -qF "ありませんでした" "$CMT"; then
  pass "対象 0 件 → mutation なし・resolved_count=0・解決対象なしコメント"
else
  fail "Case3 不一致: rc=$rc mut=[$(cat "$MUT")] out=$(cat "$OUT") cmt=$(cat "$CMT")"
fi

echo "=== Case 4: 大文字 OWNER でも自 Bot を小文字正規化して resolve ==="
threads="$(make_threads 'PRRT_u:false:vibehawk-for-hirokimry')"
printf '%s' "$threads" > "${TMP_DIR}/threads.json"
: > "${TMP_DIR}/mutation.log"; : > "${TMP_DIR}/comment.log"; : > "${TMP_DIR}/github_output"
rc=0
PATH="$STUB_DIR:$PATH" THREADS_FIXTURE="${TMP_DIR}/threads.json" MUTATION_LOG="${TMP_DIR}/mutation.log" \
  COMMENT_LOG="${TMP_DIR}/comment.log" GH_TOKEN=t REPO="HiroKimry/vibehawk" PR_NUMBER=42 OWNER="HiroKimry" \
  ISSUE_NUMBER=42 GITHUB_OUTPUT="${TMP_DIR}/github_output" bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -qx "PRRT_u" "$MUT" && grep -qx "resolved_count=1" "$OUT"; then
  pass "大文字 OWNER を正規化して自 Bot スレッドを resolve"
else
  fail "Case4 不一致: rc=$rc mut=[$(cat "$MUT")] out=$(cat "$OUT")"
fi

echo "=== Case 5: 必須 env 未設定（ISSUE_NUMBER 欠落）→ 非 0 終了 ==="
set +e
PATH="$STUB_DIR:$PATH" THREADS_FIXTURE="${TMP_DIR}/threads.json" MUTATION_LOG="${TMP_DIR}/mutation.log" \
  COMMENT_LOG="${TMP_DIR}/comment.log" GH_TOKEN=t REPO="hirokimry/vibehawk" PR_NUMBER=42 OWNER="hirokimry" \
  GITHUB_OUTPUT="${TMP_DIR}/github_output" bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then
  pass "ISSUE_NUMBER 未設定で非 0 終了"
else
  fail "ISSUE_NUMBER 未設定でも 0 終了してしまった"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
