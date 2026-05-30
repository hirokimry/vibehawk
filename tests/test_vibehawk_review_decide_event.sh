#!/usr/bin/env bash
# scripts/ci/vibehawk-review/decide-event.sh の単体テスト。
#
# 判定ルール（Issue #171: severity 不問・件数主軸、上から順、最初にマッチしたものを採用）:
#   1. unresolved >= 1 → REQUEST_CHANGES
#   2. 新規 inline 指摘の総件数 >= 1 → REQUEST_CHANGES（severity 不問）
#   3. それ以外 → APPROVE
# gh api graphql をスタブして unresolved_count を制御する。

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

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/decide-event.sh"

echo "=== scripts/ci/vibehawk-review/decide-event.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "decide-event.sh が存在する"
else
  fail "decide-event.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

make_gh_stub() {
  local count="$1"
  cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
# gh スタブ: api graphql 呼び出しで unresolved 数を返す
if [[ "\${1:-}" == "api" && "\${2:-}" == "graphql" ]]; then
  printf '%s\n' "$count"
fi
EOF
  chmod +x "$STUB_DIR/gh"
}

run_script() {
  local payload="$1" unresolved="$2"
  make_gh_stub "$unresolved"
  local output_file="${TMP_DIR}/github_output"
  : > "$output_file"
  local stdout_file="${TMP_DIR}/stdout"
  local runner_temp="${TMP_DIR}/runner_temp"
  mkdir -p "$runner_temp"
  local rc=0
  PATH="$STUB_DIR:$PATH" \
    GITHUB_OUTPUT="$output_file" \
    REPO="hirokimry/vibehawk" PR_NUMBER=42 \
    STRUCTURED_OUTPUT="$payload" \
    RUNNER_TEMP="$runner_temp" \
    bash "$SCRIPT" > "$stdout_file" 2>&1 || rc=$?
  echo "$rc"
}

OUT="${TMP_DIR}/github_output"

EMPTY_PAYLOAD='{"event":"COMMENT","body":"summary","commit_id":"sha1","comments":[]}'
rc=$(run_script "$EMPTY_PAYLOAD" "0")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=APPROVE" "$OUT" \
   && grep -qx "unresolved_count=0" "$OUT" \
   && grep -qx "new_comments_count=0" "$OUT"; then
  pass "新規 0 + unresolved=0 → APPROVE"
else
  fail "APPROVE シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

MAJOR_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha2","comments":[{"path":"a.ts","body":"🟠 **Major**: x"}]}'
rc=$(run_script "$MAJOR_PAYLOAD" "0")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=REQUEST_CHANGES" "$OUT" \
   && grep -qx "unresolved_count=0" "$OUT" \
   && grep -qx "new_comments_count=1" "$OUT"; then
  pass "Major 1 件 + unresolved=0 → REQUEST_CHANGES"
else
  fail "Major シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

CRIT_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha3","comments":[{"path":"a.ts","body":"🔴 **Critical**: x"}]}'
rc=$(run_script "$CRIT_PAYLOAD" "0")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=REQUEST_CHANGES" "$OUT" \
   && grep -qx "new_comments_count=1" "$OUT"; then
  pass "Critical 1 件 + unresolved=0 → REQUEST_CHANGES"
else
  fail "Critical シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

rc=$(run_script "$EMPTY_PAYLOAD" "2")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=REQUEST_CHANGES" "$OUT" \
   && grep -qx "unresolved_count=2" "$OUT" \
   && grep -qx "new_comments_count=0" "$OUT"; then
  pass "unresolved=2 + 新規 0 → REQUEST_CHANGES（unresolved 優先）"
else
  fail "unresolved 優先シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

MINOR_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha5","comments":[{"path":"a.ts","body":"🟡 **Minor**: x"}]}'
rc=$(run_script "$MINOR_PAYLOAD" "0")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=REQUEST_CHANGES" "$OUT" \
   && grep -qx "new_comments_count=1" "$OUT"; then
  pass "Minor 1 件 + unresolved=0 → REQUEST_CHANGES（severity 不問、Issue #171）"
else
  fail "Minor シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

TRIVIAL_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha6","comments":[{"path":"a.ts","body":"🔵 **Trivial**: x"}]}'
rc=$(run_script "$TRIVIAL_PAYLOAD" "0")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=REQUEST_CHANGES" "$OUT" \
   && grep -qx "new_comments_count=1" "$OUT"; then
  pass "Trivial 1 件 + unresolved=0 → REQUEST_CHANGES（severity 不問、Issue #171）"
else
  fail "Trivial シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

INFO_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha7","comments":[{"path":"a.ts","body":"⚪ **Info**: x"}]}'
rc=$(run_script "$INFO_PAYLOAD" "0")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=REQUEST_CHANGES" "$OUT" \
   && grep -qx "new_comments_count=1" "$OUT"; then
  pass "Info 1 件 + unresolved=0 → REQUEST_CHANGES（severity 不問、Issue #171 の核心シナリオ）"
else
  fail "Info シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

MIXED_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha8","comments":[{"path":"a.ts","body":"🟡 **Minor**: x"},{"path":"b.ts","body":"⚪ **Info**: y"},{"path":"c.ts","body":"⚪ **Info**: z"}]}'
rc=$(run_script "$MIXED_PAYLOAD" "0")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "decided_event=REQUEST_CHANGES" "$OUT" \
   && grep -qx "new_comments_count=3" "$OUT"; then
  pass "Minor 1 + Info 2 件 + unresolved=0 → REQUEST_CHANGES（total=3、severity 不問の総件数集計）"
else
  fail "混在シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

set +e
PATH="$STUB_DIR:$PATH" GITHUB_OUTPUT="$OUT" REPO="x/y" PR_NUMBER=1 \
  RUNNER_TEMP="${TMP_DIR}/runner_temp" bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then
  pass "STRUCTURED_OUTPUT 未設定で非 0 終了する"
else
  fail "STRUCTURED_OUTPUT 未設定でも 0 終了してしまった"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
