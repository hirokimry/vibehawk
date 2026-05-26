#!/usr/bin/env bash
# Issue #226 — .github/scripts/fetch-recent-review-info.sh の単体テスト
#
# gh コマンドを STUB_DIR の stub gh で差し替え（test_common_gh_helpers.sh:38-46 既存パターン踏襲）、
# fetch-recent-review-info.sh が GITHUB_OUTPUT に valid な 1 行 JSON 3 種を書き込むことを検証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/fetch-recent-review-info.sh"

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

# stub gh を作る（heredoc + chmod +x、test_common_gh_helpers.sh と同じパターン）
STUB_DIR="$(mktemp -d)"
TMP_OUTPUTS=()
cleanup() {
  rm -rf "$STUB_DIR" || true
  for f in "${TMP_OUTPUTS[@]+"${TMP_OUTPUTS[@]}"}"; do
    rm -f "$f" || true
  done
}
trap cleanup EXIT

# stub gh: 引数で挙動を分岐する（pulls/{N}/commits / pr diff / repos/{owner}/{repo}）
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
# 用途: vibehawk test_fetch_recent_review_info.sh 用 stub gh
# 引数パターンに応じて固定 fixture を返す。
case "$*" in
  *"pulls/"*"/commits"*)
    cat <<JSON
[{"sha":"abc1234567"},{"sha":"def4567890"},{"sha":"ghi7890123"}]
JSON
    ;;
  *"pr diff"*"--name-only"*)
    printf '%s\n' 'src/main.ts' 'docs/api.md' 'package-lock.json' 'tests/test_main.sh'
    ;;
  *)
    echo "gh stub: 未対応の引数: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$STUB_DIR/gh"

run_fetch() {
  local github_output_file
  github_output_file="$(mktemp)"
  TMP_OUTPUTS+=("$github_output_file")
  PATH="$STUB_DIR:$PATH" \
    REPO="${REPO:-hirokimry/vibehawk}" \
    PR_NUMBER="${PR_NUMBER:-226}" \
    PATH_FILTERS_JSON="${PATH_FILTERS_JSON:-[]}" \
    GITHUB_OUTPUT="$github_output_file" \
    VIBEHAWK_GLOB_DEBUG="${VIBEHAWK_GLOB_DEBUG:-}" \
    bash "$SCRIPT" > /dev/null
  printf '%s' "$github_output_file"
}

# GITHUB_OUTPUT から key の値を抽出する
extract_value() {
  local file="$1"
  local key="$2"
  grep -e "^${key}=" "$file" | cut -d= -f2-
}

echo "Case 1: PATH_FILTERS_JSON=[] で全ファイルが files_selected_json に入る"
output_file="$(run_fetch)"
selected_value="$(extract_value "$output_file" "files_selected_json")"
ignored_value="$(extract_value "$output_file" "files_ignored_json")"
selected_len="$(printf '%s' "$selected_value" | jq -r 'length')"
ignored_len="$(printf '%s' "$ignored_value" | jq -r 'length')"
if [[ "$selected_len" == "4" && "$ignored_len" == "0" ]]; then
  pass "Case 1"
else
  fail "Case 1: selected=$selected_len (期待 4), ignored=$ignored_len (期待 0)"
fi

echo "Case 2: PATH_FILTERS_JSON=[\"!docs/**\"] で docs/api.md が ignored に分類される"
# Windows での glob_match 挙動を診断するため VIBEHAWK_GLOB_DEBUG を有効化
PATH_FILTERS_JSON='["!docs/**"]' VIBEHAWK_GLOB_DEBUG=1 output_file="$(run_fetch)"
ignored_value="$(extract_value "$output_file" "files_ignored_json")"
selected_value="$(extract_value "$output_file" "files_selected_json")"
# デバッグ情報を stderr に出力（Windows での挙動差を診断、PR #235 windows fail 調査用、Issue #229）
{
  echo "[DEBUG] BASH_VERSION=$BASH_VERSION OS=${OSTYPE:-unknown}"
  echo "[DEBUG] selected_value=$selected_value"
  echo "[DEBUG] ignored_value=$ignored_value"
  # 直接 case マッチを試す（process substitution 経由せず）
  pat='docs/*'
  test_path='docs/api.md'
  # shellcheck disable=SC2254
  case "$test_path" in
    $pat) echo '[DEBUG] direct case docs/api.md in docs/* -> match' ;;
    *)    echo '[DEBUG] direct case docs/api.md in docs/* -> NO match' ;;
  esac
} >&2
if printf '%s' "$ignored_value" | jq -e 'index("docs/api.md") != null' > /dev/null \
  && ! printf '%s' "$selected_value" | jq -e 'index("docs/api.md") != null' > /dev/null; then
  pass "Case 2"
else
  fail "Case 2: docs/api.md が ignored に分類されていない（selected=$selected_value, ignored=$ignored_value）"
fi

echo "Case 3: GITHUB_OUTPUT の 3 出力が valid な 1 行 JSON である"
output_file="$(run_fetch)"
ok=1
for key in commits_json files_selected_json files_ignored_json; do
  value="$(extract_value "$output_file" "$key")"
  if ! printf '%s' "$value" | jq -e '.' > /dev/null 2>&1; then
    ok=0
    echo "  $key の値が valid JSON でない: $value" >&2
  fi
  # 1 行 JSON 検証（改行を含まない）— grep -q $'\n' は改行を含むパターンが行ベース処理と
  # 衝突して常に true を返してしまうため、tr で改行文字数を数える方式に変更。
  nl_count=$(printf '%s' "$value" | tr -cd '\n' | wc -c | tr -d '[:space:]')
  if [[ "$nl_count" -gt 0 ]]; then
    ok=0
    echo "  $key の値が複数行（${nl_count} 改行を含む）" >&2
  fi
done
if [[ "$ok" -eq 1 ]]; then
  pass "Case 3"
else
  fail "Case 3: GITHUB_OUTPUT の 3 出力に invalid JSON か複数行が混入"
fi

echo "Case 4: commits_json が sha フィールドを持つオブジェクト配列"
output_file="$(run_fetch)"
commits_value="$(extract_value "$output_file" "commits_json")"
if printf '%s' "$commits_value" | jq -e '. | type == "array" and (.[0] | has("sha"))' > /dev/null; then
  pass "Case 4"
else
  fail "Case 4: commits_json が sha 配列構造でない"
fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
