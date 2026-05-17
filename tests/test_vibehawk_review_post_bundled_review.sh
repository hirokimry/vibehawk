#!/usr/bin/env bash
# scripts/ci/vibehawk-review/post-bundled-review.sh の単体テスト。
#
# - schema validation 失敗時の skip 経路（exit 0 + ::warning::）
# - DECIDED_EVENT 空 / 不正値時の skip 経路
# - 正常系で gh api -X POST が呼ばれ、payload の .event が DECIDED_EVENT で
#   上書きされる

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

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/post-bundled-review.sh"

echo "=== scripts/ci/vibehawk-review/post-bundled-review.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "post-bundled-review.sh が存在する"
else
  fail "post-bundled-review.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

# gh スタブ: api -X POST 呼び出し時、--input 引数のファイル中身をログに出して exit 0
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
gh_log="${GH_STUB_LOG:-/dev/null}"
{
  echo "=== gh stub call ==="
  for arg in "$@"; do printf 'ARG: %s\n' "$arg"; done
  # --input <file> の中身を出す
  prev=""
  for arg in "$@"; do
    if [[ "$prev" == "--input" ]]; then
      echo "=== input file content ==="
      cat "$arg"
      echo "=== end input ==="
    fi
    prev="$arg"
  done
} >> "$gh_log"
exit 0
STUB
chmod +x "$STUB_DIR/gh"

run_script() {
  # Usage: run_script <structured_output> <decided_event>
  local payload="$1" decided="$2"
  local gh_log="${TMP_DIR}/gh.log"
  : > "$gh_log"
  local stdout_file="${TMP_DIR}/stdout"
  local runner_temp="${TMP_DIR}/runner_temp"
  mkdir -p "$runner_temp"
  local rc=0
  PATH="$STUB_DIR:$PATH" \
    GH_STUB_LOG="$gh_log" \
    REPO="hirokimry/vibehawk" PR_NUMBER=42 \
    STRUCTURED_OUTPUT="$payload" \
    DECIDED_EVENT="$decided" \
    RUNNER_TEMP="$runner_temp" \
    bash "$SCRIPT" > "$stdout_file" 2>&1 || rc=$?
  echo "$rc"
}

GH_LOG="${TMP_DIR}/gh.log"
STDOUT="${TMP_DIR}/stdout"

# シナリオ 1: 正常系（event=COMMENT placeholder、DECIDED_EVENT=APPROVE で上書き → POST 実行）
VALID='{"event":"COMMENT","body":"summary text","commit_id":"abc123","comments":[]}'
rc=$(run_script "$VALID" "APPROVE")
if [[ "$rc" -eq 0 ]] \
   && grep -qF "ARG: api" "$GH_LOG" \
   && grep -qF "ARG: -X" "$GH_LOG" \
   && grep -qF "ARG: POST" "$GH_LOG" \
   && grep -qF "repos/hirokimry/vibehawk/pulls/42/reviews" "$GH_LOG"; then
  pass "正常系で gh api -X POST が呼ばれる"
else
  fail "POST 呼び出しが想定と異なる: rc=$rc, gh_log=$(cat "$GH_LOG")"
fi

# 同じシナリオで、payload の .event が APPROVE に上書きされていることを検証
# jq の出力は pretty-printed なので `"event": "APPROVE"`（コロン後に空白あり）になる
if grep -qE '"event":\s*"APPROVE"' "$GH_LOG"; then
  pass "payload の .event が DECIDED_EVENT で上書きされる"
else
  fail ".event の上書きが反映されなかった: gh_log=$(cat "$GH_LOG")"
fi

# シナリオ 2: schema validation 失敗 → skip（exit 0 + warning、gh は呼ばれない）
INVALID='{"event":"BOGUS","body":"","commit_id":"","comments":[]}'
rc=$(run_script "$INVALID" "APPROVE")
if [[ "$rc" -eq 0 ]] \
   && ! grep -qF "ARG: -X" "$GH_LOG" \
   && grep -qF "::warning::" "$STDOUT"; then
  pass "schema validation 失敗 → skip (gh 未呼出 + ::warning::)"
else
  fail "schema 失敗時の skip 挙動が想定と異なる: rc=$rc, gh_log=$(cat "$GH_LOG"), stdout=$(cat "$STDOUT")"
fi

# シナリオ 3: DECIDED_EVENT 空 → skip
rc=$(run_script "$VALID" "")
if [[ "$rc" -eq 0 ]] \
   && ! grep -qF "ARG: -X" "$GH_LOG" \
   && grep -qF "::warning::" "$STDOUT" \
   && grep -qF "decide_event step の出力" "$STDOUT"; then
  pass "DECIDED_EVENT 空 → skip"
else
  fail "DECIDED_EVENT 空時の挙動が想定と異なる: rc=$rc, stdout=$(cat "$STDOUT")"
fi

# シナリオ 4: DECIDED_EVENT 不正値 → skip
rc=$(run_script "$VALID" "INVALID_VALUE")
if [[ "$rc" -eq 0 ]] \
   && ! grep -qF "ARG: -X" "$GH_LOG" \
   && grep -qF "::warning::" "$STDOUT" \
   && grep -qF "GitHub Reviews API の許容値" "$STDOUT"; then
  pass "DECIDED_EVENT 不正値 → skip"
else
  fail "DECIDED_EVENT 不正時の挙動が想定と異なる: rc=$rc, stdout=$(cat "$STDOUT")"
fi

# シナリオ 5: 必須 env (REPO / PR_NUMBER / STRUCTURED_OUTPUT / RUNNER_TEMP) 欠落
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
