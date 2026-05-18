#!/usr/bin/env bash
# scripts/ci/vibehawk-review/find-prev-summary.sh の単体テスト。
#
# gh / git をスタブして 3 シナリオを検証する:
#   - 前回サマリ未検出 → incremental=false, 全フィールド空
#   - 前回サマリあり + prev_sha が現ブランチに含まれる → incremental=true, prev_sha..HEAD
#   - 前回サマリあり + prev_sha が見つからない（force push 想定） → incremental=false, base..HEAD

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

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

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/find-prev-summary.sh"

echo "=== scripts/ci/vibehawk-review/find-prev-summary.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "find-prev-summary.sh が存在する"
else
  fail "find-prev-summary.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

make_gh_stub() {
  # 引数 1: gh api stdout として返す JSON（reviews 一覧 raw、jq -cs で集約される側）
  local payload_file="${TMP_DIR}/gh_payload.json"
  printf '%s' "$1" > "$payload_file"
  cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
# gh スタブ: api 呼び出しに対して固定 JSON を返す（その他は何もしない）
case "\${1:-}" in
  api)
    cat "$payload_file"
    ;;
  *)
    : # noop
    ;;
esac
EOF
  chmod +x "$STUB_DIR/gh"
}

make_git_stub() {
  # 引数 1: cat-file の exit code (0/1)
  # 引数 2: merge-base --is-ancestor の exit code (0/1)
  # 引数 3: merge-base origin/<base> HEAD の stdout
  local catfile_rc="$1" ancestor_rc="$2" base_sha="$3"
  cat > "$STUB_DIR/git" <<EOF
#!/usr/bin/env bash
sub="\${1:-}"
case "\$sub" in
  cat-file)
    exit $catfile_rc
    ;;
  merge-base)
    if [[ "\${2:-}" == "--is-ancestor" ]]; then
      exit $ancestor_rc
    fi
    printf '%s\n' "$base_sha"
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$STUB_DIR/git"
}

run_script() {
  local output_file="${TMP_DIR}/github_output"
  : > "$output_file"
  local stdout_file="${TMP_DIR}/stdout"
  local rc=0
  PATH="$STUB_DIR:$PATH" GITHUB_OUTPUT="$output_file" \
    REPO="hirokimry/vibehawk" PR_NUMBER=42 OWNER="hirokimry" BASE_REF="main" \
    bash "$SCRIPT" > "$stdout_file" 2>&1 || rc=$?
  echo "$rc"
}

OUT="${TMP_DIR}/github_output"

# シナリオ 1: 前回サマリ未検出（reviews が空配列 = jq -cs で last // empty が空）
make_gh_stub "[]"
make_git_stub 0 0 ""
rc=$(run_script)
if [[ "$rc" -eq 0 ]] \
   && grep -qx "incremental=false" "$OUT" \
   && grep -qx "comment_id=" "$OUT" \
   && grep -qx "prev_sha=" "$OUT" \
   && grep -qx "review_range=" "$OUT"; then
  pass "前回サマリ未検出 → 全フィールド空で incremental=false"
else
  fail "未検出シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

# シナリオ 2: 前回サマリあり + prev_sha がブランチに含まれる
PREV_SHA="abc123def456"
REVIEW_JSON=$(cat <<EOF
[{"id": 999, "user": {"login": "vibehawk-for-hirokimry[bot]"}, "submitted_at": "2026-01-01T00:00:00Z", "body": "Summary text\n<!-- vibehawk:summary -->\n<!-- vibehawk:sha=${PREV_SHA} -->"}]
EOF
)
make_gh_stub "$REVIEW_JSON"
make_git_stub 0 0 ""
rc=$(run_script)
if [[ "$rc" -eq 0 ]] \
   && grep -qx "incremental=true" "$OUT" \
   && grep -qx "comment_id=999" "$OUT" \
   && grep -qx "prev_sha=${PREV_SHA}" "$OUT" \
   && grep -qx "review_range=${PREV_SHA}..HEAD" "$OUT"; then
  pass "通常 push 検出 → incremental=true, range=prev_sha..HEAD"
else
  fail "通常 push シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

# シナリオ 3: 前回サマリあり + force push（cat-file or is-ancestor が失敗）→ base..HEAD
make_gh_stub "$REVIEW_JSON"
make_git_stub 1 1 "deadbeef00"
rc=$(run_script)
if [[ "$rc" -eq 0 ]] \
   && grep -qx "incremental=false" "$OUT" \
   && grep -qx "prev_sha=${PREV_SHA}" "$OUT" \
   && grep -qx "review_range=deadbeef00..HEAD" "$OUT"; then
  pass "force push 検出 → incremental=false, range=base_sha..HEAD"
else
  fail "force push シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

# シナリオ 4: 前回サマリあり + SHA マーカー抽出失敗 → 完全再レビュー（incremental=false, prev_sha 空）
REVIEW_NO_SHA=$(cat <<'EOF'
[{"id": 1000, "user": {"login": "vibehawk-for-hirokimry[bot]"}, "submitted_at": "2026-01-01T00:00:00Z", "body": "Old summary without SHA marker\n<!-- vibehawk:summary -->"}]
EOF
)
make_gh_stub "$REVIEW_NO_SHA"
make_git_stub 0 0 ""
rc=$(run_script)
if [[ "$rc" -eq 0 ]] \
   && grep -qx "incremental=false" "$OUT" \
   && grep -qx "comment_id=1000" "$OUT" \
   && grep -qx "prev_sha=" "$OUT" \
   && grep -qx "review_range=" "$OUT"; then
  pass "SHA マーカー欠落 → comment_id だけ残し、prev_sha と range は空"
else
  fail "SHA マーカー欠落シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

# シナリオ 5: 必須 env 欠落
set +e
PATH="$STUB_DIR:$PATH" GITHUB_OUTPUT="$OUT" REPO="x/y" PR_NUMBER=1 bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then
  pass "必須 env (OWNER/BASE_REF) 未設定で非 0 終了する"
else
  fail "必須 env 未設定でも 0 終了してしまった"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
