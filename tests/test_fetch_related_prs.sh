#!/usr/bin/env bash
# Issue #228 — .github/scripts/fetch-related-prs.sh の単体テスト
#
# gh コマンドを stub で差し替え（test_common_gh_helpers.sh パターン踏襲）、
# fetch-related-prs.sh が GITHUB_OUTPUT に valid な 1 行 JSON を書き込むことを検証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/fetch-related-prs.sh"

PASSED=0
FAILED=0

pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  FAILED=$((FAILED + 1))
}

if [[ ! -x "$SCRIPT" ]]; then
  fail "${SCRIPT} が実行可能でない"
  exit 1
fi

STUB_DIR="$(mktemp -d)"
TMP_OUTPUTS=()
cleanup() {
  rm -rf "$STUB_DIR" || true
  for f in "${TMP_OUTPUTS[@]+"${TMP_OUTPUTS[@]}"}"; do
    rm -f "$f" || true
  done
}
trap cleanup EXIT

# stub gh: pr view → title 返す / api search/issues → 配列返す
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"pr view"*"--json title"*)
    echo "✨ feat: sticky walkthrough に新機能追加"
    ;;
  *"api search/issues"*)
    cat <<JSON
{"items":[{"number":150,"title":"既存 sticky 仕様変更"},{"number":160,"title":"walkthrough テスト追加"}]}
JSON
    ;;
  *)
    echo "gh stub: 未対応 $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$STUB_DIR/gh"

run_fetch() {
  local out
  out="$(mktemp)"
  TMP_OUTPUTS+=("$out")
  PATH="$STUB_DIR:$PATH" \
    REPO="hirokimry/vibehawk" \
    PR_NUMBER="228" \
    GITHUB_OUTPUT="$out" \
    bash "$SCRIPT" > /dev/null
  printf '%s' "$out"
}

extract_value() {
  grep -e "^${2}=" "$1" | cut -d= -f2-
}

echo "Case 1: stub gh からの取得結果が related_prs_json に書き込まれる"
out_file="$(run_fetch)"
value="$(extract_value "$out_file" "related_prs_json")"
if printf '%s' "$value" | jq -e '. | type == "array"' > /dev/null \
  && [ "$(printf '%s' "$value" | jq -r 'length')" = "2" ]; then
  pass "Case 1"
else
  fail "Case 1: related_prs_json が期待形式でない（value=$value）"
fi

echo "Case 2: 自身の PR 番号（228）が結果に含まれない"
# stub gh が返す items に 228 を含めて self exclude を確認
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"pr view"*"--json title"*)
    echo "✨ feat: sticky walkthrough に新機能追加"
    ;;
  *"api search/issues"*)
    cat <<JSON
{"items":[{"number":228,"title":"自身"},{"number":300,"title":"他"}]}
JSON
    ;;
esac
EOF
out_file="$(run_fetch)"
value="$(extract_value "$out_file" "related_prs_json")"
if printf '%s' "$value" | jq -e 'all(.[]; .number != 228)' > /dev/null; then
  pass "Case 2"
else
  fail "Case 2: 自身の PR 番号 228 が related_prs_json に含まれている（value=$value）"
fi

echo "Case 3: 1 行 JSON である（改行を含まない）"
nl_count=$(printf '%s' "$value" | tr -cd '\n' | wc -c | tr -d '[:space:]')
if [ "$nl_count" -eq 0 ]; then
  pass "Case 3"
else
  fail "Case 3: related_prs_json に改行が含まれる（nl=$nl_count）"
fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
