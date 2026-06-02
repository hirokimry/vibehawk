#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/lib-review-threads.sh の単体テスト（Issue #289、CodeRabbit 指摘対応）。
#   - fetch_all_review_threads が複数ページを cursor で全走査して集約する（first:100 取りこぼし対策）
#   - 単一ページ（pageInfo なし）でも動く
# gh api graphql をスタブし、after カーソルの有無でページを切り替える。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

LIB="${REPO_ROOT}/scripts/ci/vibehawk-chat/lib-review-threads.sh"
echo "=== lib-review-threads.sh 単体テスト ==="
if [[ -f "$LIB" ]]; then pass "存在する"; else fail "存在しない"; exit 1; fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT
STUB_DIR="${TMP_DIR}/stub"; mkdir -p "$STUB_DIR"

# gh スタブ: graphql で after: $cursor 変数の有無により page1/page2 を返す。
#   - 引数に cursor= を含む（2 ページ目要求）→ PAGE2_FIXTURE
#   - 含まない（1 ページ目）→ PAGE1_FIXTURE
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "api" && "${2:-}" == "graphql" ]]; then
  if printf '%s ' "$@" | grep -q 'cursor='; then
    cat "$PAGE2_FIXTURE"
  else
    cat "$PAGE1_FIXTURE"
  fi
  exit 0
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

# page1: hasNextPage=true, endCursor=C1, node A（未解決・自Bot）
cat > "${TMP_DIR}/page1.json" <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":true,"endCursor":"C1"},"nodes":[{"id":"A","isResolved":false,"comments":{"nodes":[{"author":{"login":"vibehawk-for-x"}}]}}]}}}}}
EOF
# page2: hasNextPage=false, node B（解決済み）
cat > "${TMP_DIR}/page2.json" <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":"C2"},"nodes":[{"id":"B","isResolved":true,"comments":{"nodes":[{"author":{"login":"vibehawk-for-x"}}]}}]}}}}}
EOF
# single: pageInfo なし（旧フィクスチャ互換）
cat > "${TMP_DIR}/single.json" <<'EOF'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"S","isResolved":false,"comments":{"nodes":[{"author":{"login":"vibehawk-for-x"}}]}}]}}}}}
EOF

run_fetch() {
  # $1 page1 fixture  $2 page2 fixture
  PATH="$STUB_DIR:$PATH" PAGE1_FIXTURE="$1" PAGE2_FIXTURE="$2" bash -c '
    . "'"$LIB"'"
    fetch_all_review_threads "owner" "repo" 42
  '
}

echo "=== Case 1: 2 ページを全走査して node A + B を集約 ==="
out="$(run_fetch "${TMP_DIR}/page1.json" "${TMP_DIR}/page2.json")"
count="$(printf '%s' "$out" | jq '.data.repository.pullRequest.reviewThreads.nodes | length')"
has_a="$(printf '%s' "$out" | jq '[.data.repository.pullRequest.reviewThreads.nodes[].id] | index("A") != null')"
has_b="$(printf '%s' "$out" | jq '[.data.repository.pullRequest.reviewThreads.nodes[].id] | index("B") != null')"
if [[ "$count" -eq 2 && "$has_a" == "true" && "$has_b" == "true" ]]; then
  pass "2 ページ集約（node A + B、計 2 件）"
else
  fail "Case1 不一致: count=$count out=$(printf '%s' "$out" | head -c 200)"
fi

echo "=== Case 2: 単一ページ（pageInfo なし）でも 1 件返す ==="
out="$(run_fetch "${TMP_DIR}/single.json" "${TMP_DIR}/single.json")"
count="$(printf '%s' "$out" | jq '.data.repository.pullRequest.reviewThreads.nodes | length')"
if [[ "$count" -eq 1 ]]; then
  pass "単一ページ（pageInfo なし）→ 1 件・無限ループしない"
else
  fail "Case2 不一致: count=$count"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
