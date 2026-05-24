#!/usr/bin/env bash
# scripts/ci/vibehawk-review-skip-mark/post-skip-check-run.sh の単体テスト。
#
# 実際の GitHub API は呼ばない。PATH に gh スタブを差し込み、`gh api -X POST` が
# 想定通り `/repos/${REPO}/check-runs` に固定パラメータで呼ばれることを検証する。
#
# Issue #178 で vibehawk-review-skip-mark.yml から切り出された .sh のテスト。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

TARGET="${REPO_ROOT}/scripts/ci/vibehawk-review-skip-mark/post-skip-check-run.sh"

echo "=== scripts/ci/vibehawk-review-skip-mark/post-skip-check-run.sh 単体テスト ==="

if [[ -f "$TARGET" ]]; then
  pass "post-skip-check-run.sh が存在する"
else
  fail "post-skip-check-run.sh が存在しない"
  exit 1
fi

if [[ -x "$TARGET" ]]; then
  pass "post-skip-check-run.sh に実行権限が付いている"
else
  fail "post-skip-check-run.sh に実行権限が付いていない"
fi

WORK_DIR="$(mktemp -d)"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR" "$STUB_DIR"' EXIT

cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  printf '%s\n' "$arg"
done > "${GH_STUB_LOG:-/dev/null}"
EOF
chmod +x "$STUB_DIR/gh"

GH_STUB_LOG="${WORK_DIR}/gh-args.log"

: > "$GH_STUB_LOG"
PATH="$STUB_DIR:$PATH" \
  GH_STUB_LOG="$GH_STUB_LOG" \
  GH_TOKEN=dummy \
  HEAD_SHA=abc123def456 \
  REPO=hirokimry/vibehawk \
  bash "$TARGET"

expected_args="api
-X
POST
/repos/hirokimry/vibehawk/check-runs
-f
name=vibehawk
-f
head_sha=abc123def456
-f
status=completed
-f
conclusion=success
-f
output[title]=vibehawk-review skipped (paths-ignore matched)
-f
output[summary]=All changed files matched vibehawk-review.yml paths-ignore patterns (Issue #65). LLM review skipped to keep API cost at zero. Posted by vibehawk-review-skip-mark.yml (Issue #157)."

actual_args="$(cat "$GH_STUB_LOG")"
if [[ "$actual_args" == "$expected_args" ]]; then
  pass "gh api -X POST が想定の引数で呼ばれる"
else
  fail "gh の呼び出し引数が想定と異なる"
  echo "  期待:"
  echo "$expected_args" | sed 's/^/    /'
  echo "  実際:"
  echo "$actual_args" | sed 's/^/    /'
fi

check_arg() {
  local needle="$1"
  local label="$2"
  # `--` で grep のオプション解析を打ち切り、`-X` 等を pattern として扱う
  if grep -Fxq -- "$needle" "$GH_STUB_LOG"; then
    pass "$label"
  else
    fail "$label が gh の引数に含まれない"
  fi
}
check_arg "api" "gh api サブコマンドが指定される"
check_arg "-X" "-X フラグが指定される"
check_arg "POST" "POST メソッドが指定される"
check_arg "/repos/hirokimry/vibehawk/check-runs" "/repos/<owner>/<repo>/check-runs エンドポイントが指定される"
check_arg "name=vibehawk" "name=vibehawk が固定指定される（branch protection 一致）"
check_arg "head_sha=abc123def456" "head_sha=<HEAD_SHA> が指定される"
check_arg "status=completed" "status=completed が固定指定される"
check_arg "conclusion=success" "conclusion=success が固定指定される"
check_arg "output[title]=vibehawk-review skipped (paths-ignore matched)" "output[title] が Issue #65 経緯を残す固定文"
if grep -F "Issue #65" "$GH_STUB_LOG" > /dev/null && grep -F "Issue #157" "$GH_STUB_LOG" > /dev/null; then
  pass "output[summary] に Issue #65 / #157 の出典が含まれる"
else
  fail "output[summary] に出典が含まれない"
fi

# 念のため `env -u <VAR>` で子 env から明示的に除去する（PR #184 CI 失敗対策）。
set +e
err_out="$(
  PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy \
  REPO=hirokimry/vibehawk \
  env -u HEAD_SHA bash "$TARGET" 2>&1
)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -F "HEAD_SHA が必須です" > /dev/null; then
  pass "HEAD_SHA 未設定で exit 非0 + エラーメッセージ"
else
  fail "HEAD_SHA 未設定時の挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

set +e
err_out="$(
  PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy \
  HEAD_SHA=abc \
  env -u REPO bash "$TARGET" 2>&1
)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -F "REPO が必須です" > /dev/null; then
  pass "REPO 未設定で exit 非0 + エラーメッセージ"
else
  fail "REPO 未設定時の挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
