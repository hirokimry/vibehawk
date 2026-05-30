#!/usr/bin/env bash
# scripts/ci/vibehawk-review/post-status-check.sh の単体テスト。
#
# review.state（APPROVED / CHANGES_REQUESTED / 他）→ check-runs conclusion
# (success / failure / neutral) の決定論的マッピングを検証する。
# substantive review が見つからないときの fallback、review 未投稿時の
# neutral 経路もカバーする。

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

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/post-status-check.sh"

echo "=== scripts/ci/vibehawk-review/post-status-check.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "post-status-check.sh が存在する"
else
  fail "post-status-check.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

make_gh_stub() {
  local reviews_json="$1"
  local reviews_file="${TMP_DIR}/reviews.json"
  printf '%s' "$reviews_json" > "$reviews_file"
  cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
# gh スタブ:
#   - api <endpoint>（POST 以外）  → reviews JSON を返す（テストでは reviews 取得しか呼ばれない）
#   - api -X POST <endpoint> --field ...  → 引数を gh_post.log に記録
#
gh_log="\${GH_STUB_LOG:-/dev/null}"

is_post=0
for arg in "\$@"; do
  if [[ "\$arg" == "POST" ]]; then is_post=1; fi
done

if [[ "\$is_post" -eq 1 ]]; then
  {
    echo "=== gh stub POST ==="
    for arg in "\$@"; do printf 'ARG: %s\n' "\$arg"; done
  } >> "\$gh_log"
  exit 0
fi

# 非 POST（reviews 取得）
cat "$reviews_file"
EOF
  chmod +x "$STUB_DIR/gh"
}

run_script() {
  make_gh_stub "$1"
  local gh_log="${TMP_DIR}/gh.log"
  : > "$gh_log"
  local stdout_file="${TMP_DIR}/stdout"
  local rc=0
  PATH="$STUB_DIR:$PATH" \
    GH_STUB_LOG="$gh_log" \
    REPO="hirokimry/vibehawk" PR_NUMBER=42 \
    HEAD_SHA="abc123" OWNER="hirokimry" \
    bash "$SCRIPT" > "$stdout_file" 2>&1 || rc=$?
  echo "$rc"
}

GH_LOG="${TMP_DIR}/gh.log"
STDOUT="${TMP_DIR}/stdout"

APPROVED_REVIEW='[{"id":1,"user":{"login":"vibehawk-for-hirokimry[bot]"},"commit_id":"abc123","state":"APPROVED","body":"All good","submitted_at":"2026-01-01T00:00:00Z"}]'
rc=$(run_script "$APPROVED_REVIEW")
if [[ "$rc" -eq 0 ]] \
   && grep -qF "ARG: conclusion=success" "$GH_LOG" \
   && grep -qF "ARG: output[title]=vibehawk: APPROVED" "$GH_LOG"; then
  pass "APPROVED → conclusion=success, title=vibehawk: APPROVED"
else
  fail "APPROVED シナリオの出力が想定と異なる: rc=$rc, gh_log=$(cat "$GH_LOG"), stdout=$(cat "$STDOUT")"
fi

CHANGES_REVIEW='[{"id":2,"user":{"login":"vibehawk-for-hirokimry[bot]"},"commit_id":"abc123","state":"CHANGES_REQUESTED","body":"Fix it","submitted_at":"2026-01-01T00:00:00Z"}]'
rc=$(run_script "$CHANGES_REVIEW")
if [[ "$rc" -eq 0 ]] \
   && grep -qF "ARG: conclusion=failure" "$GH_LOG" \
   && grep -qF "ARG: output[title]=vibehawk: CHANGES_REQUESTED" "$GH_LOG"; then
  pass "CHANGES_REQUESTED → conclusion=failure"
else
  fail "CHANGES_REQUESTED シナリオの出力が想定と異なる: rc=$rc, gh_log=$(cat "$GH_LOG")"
fi

rc=$(run_script "[]")
if [[ "$rc" -eq 0 ]] \
   && grep -qF "ARG: conclusion=neutral" "$GH_LOG" \
   && grep -qF "ARG: output[title]=vibehawk: review 未投稿" "$GH_LOG"; then
  pass "review 未投稿 → conclusion=neutral + title=vibehawk: review 未投稿"
else
  fail "review 未投稿シナリオの出力が想定と異なる: rc=$rc, gh_log=$(cat "$GH_LOG")"
fi

COMMENTED_REVIEW='[{"id":3,"user":{"login":"vibehawk-for-hirokimry[bot]"},"commit_id":"abc123","state":"COMMENTED","body":"","submitted_at":"2026-01-01T00:00:00Z"}]'
rc=$(run_script "$COMMENTED_REVIEW")
if [[ "$rc" -eq 0 ]] \
   && grep -qF "ARG: conclusion=neutral" "$GH_LOG" \
   && grep -qF "ARG: output[title]=vibehawk: COMMENTED" "$GH_LOG"; then
  pass "substantive なし → fallback で COMMENTED → conclusion=neutral"
else
  fail "fallback シナリオの出力が想定と異なる: rc=$rc, gh_log=$(cat "$GH_LOG")"
fi

OTHER_REVIEW='[{"id":4,"user":{"login":"some-other-bot[bot]"},"commit_id":"abc123","state":"APPROVED","body":"hi","submitted_at":"2026-01-01T00:00:00Z"}]'
rc=$(run_script "$OTHER_REVIEW")
if [[ "$rc" -eq 0 ]] \
   && grep -qF "ARG: conclusion=neutral" "$GH_LOG" \
   && grep -qF "vibehawk: review 未投稿" "$GH_LOG"; then
  pass "他人 review は無視される → review 未投稿 neutral"
else
  fail "他人 review 無視シナリオの出力が想定と異なる: rc=$rc, gh_log=$(cat "$GH_LOG")"
fi

WRONG_SHA='[{"id":5,"user":{"login":"vibehawk-for-hirokimry[bot]"},"commit_id":"xxx999","state":"APPROVED","body":"stale","submitted_at":"2026-01-01T00:00:00Z"}]'
rc=$(run_script "$WRONG_SHA")
if [[ "$rc" -eq 0 ]] \
   && grep -qF "ARG: conclusion=neutral" "$GH_LOG" \
   && grep -qF "vibehawk: review 未投稿" "$GH_LOG"; then
  pass "別 commit_id の review は弾かれる → neutral"
else
  fail "別 commit_id シナリオの出力が想定と異なる: rc=$rc, gh_log=$(cat "$GH_LOG")"
fi

set +e
PATH="$STUB_DIR:$PATH" bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then
  pass "必須 env 全欠落で非 0 終了する"
else
  fail "必須 env 全欠落でも 0 終了してしまった"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
