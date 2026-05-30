#!/usr/bin/env bash
# Issue #228 — .github/scripts/fetch-suggested-reviewers.sh の単体テスト
#
# gh コマンドを stub で差し替え、CODEOWNERS と git log の両経路を検証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/fetch-suggested-reviewers.sh"

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
SANDBOX_DIR="$(mktemp -d)"
TMP_OUTPUTS=()
cleanup() {
  rm -rf "$STUB_DIR" "$SANDBOX_DIR" || true
  for f in "${TMP_OUTPUTS[@]+"${TMP_OUTPUTS[@]}"}"; do
    rm -f "$f" || true
  done
}
trap cleanup EXIT

# stub gh: pr diff → 変更ファイル一覧
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"pr diff"*"--name-only"*)
    printf '%s\n' 'src/main.ts' 'docs/api.md' 'tests/test_main.sh'
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
    PR_AUTHOR="hirokimry" \
    GITHUB_OUTPUT="$out" \
    bash "$SCRIPT" > /dev/null 2>&1
  printf '%s' "$out"
}

extract_value() {
  grep -e "^${2}=" "$1" | cut -d= -f2-
}

echo "Case 1: CODEOWNERS 経由で reviewer が抽出される（PR 作成者は除外）"
cd "$SANDBOX_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
mkdir -p .github
cat > .github/CODEOWNERS <<'OWNERS'
# Sample
src/* @alice @bob @hirokimry
docs/* @carol
OWNERS
git add -A && git commit -q -m "init"
out_file="$(run_fetch)"
value="$(extract_value "$out_file" "suggested_reviewers_json")"
# alice, bob, carol が抽出されて hirokimry が除外、最大 3 名
if printf '%s' "$value" | jq -e 'index("alice") != null' > /dev/null \
  && printf '%s' "$value" | jq -e 'index("bob") != null' > /dev/null \
  && printf '%s' "$value" | jq -e 'index("carol") != null' > /dev/null \
  && printf '%s' "$value" | jq -e 'all(.[]; . != "hirokimry")' > /dev/null \
  && [ "$(printf '%s' "$value" | jq 'length')" -le 3 ]; then
  pass "Case 1"
else
  fail "Case 1: CODEOWNERS 経由の reviewer 抽出が期待通りでない（value=$value）"
fi
cd "$REPO_ROOT"

echo "Case 2: CODEOWNERS 不在の場合は git log fallback（自己除外）"
cd "$(mktemp -d)"
git init -q
git config user.email "alice@example.com"
git config user.name "Alice"
echo "test" > a.txt && git add . && git commit -q -m "c1"
git config user.email "bob@example.com"
git config user.name "Bob"
echo "test2" > b.txt && git add . && git commit -q -m "c2"
out_file="$(run_fetch)"
value="$(extract_value "$out_file" "suggested_reviewers_json")"
# git log から alice, bob が抽出される（hirokimry は git log にも CODEOWNERS にも無いので除外関係なし）
if printf '%s' "$value" | jq -e '. | type == "array"' > /dev/null \
  && [ "$(printf '%s' "$value" | jq 'length')" -ge 1 ]; then
  pass "Case 2"
else
  fail "Case 2: git log fallback が期待通りでない（value=$value）"
fi
cd "$REPO_ROOT"

echo "Case 3: 1 行 JSON である"
nl_count=$(printf '%s' "$value" | tr -cd '\n' | wc -c | tr -d '[:space:]')
if [ "$nl_count" -eq 0 ]; then
  pass "Case 3"
else
  fail "Case 3: suggested_reviewers_json に改行が含まれる"
fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
