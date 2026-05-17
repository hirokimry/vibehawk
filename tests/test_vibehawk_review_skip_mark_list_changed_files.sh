#!/usr/bin/env bash
# scripts/ci/vibehawk-review-skip-mark/list-changed-files.sh の単体テスト。
#
# 実際の GitHub API は呼ばない（CI で gh 認証情報を必須にしないため）。
# PATH に gh スタブを差し込み、想定通り `gh api --paginate ... --jq '.[].filename'`
# が呼ばれ、changed_files.txt と $GITHUB_OUTPUT が更新されることを検証する。
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

TARGET="${REPO_ROOT}/scripts/ci/vibehawk-review-skip-mark/list-changed-files.sh"

echo "=== scripts/ci/vibehawk-review-skip-mark/list-changed-files.sh 単体テスト ==="

if [[ -f "$TARGET" ]]; then
  pass "list-changed-files.sh が存在する"
else
  fail "list-changed-files.sh が存在しない"
  exit 1
fi

if [[ -x "$TARGET" ]]; then
  pass "list-changed-files.sh に実行権限が付いている"
else
  fail "list-changed-files.sh に実行権限が付いていない"
fi

# 一時作業ディレクトリ（cwd を切り替えて changed_files.txt を生成させる）
WORK_DIR="$(mktemp -d)"
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR" "$STUB_DIR"' EXIT

# gh スタブ: gh_api_paginated 経由で `gh api --paginate <endpoint> --jq <filter>` を呼ぶ。
# このスタブは固定のファイル一覧を 1 行 1 ファイルで stdout に流す。
cat > "$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
# 引数を記録（args.log に追記）。printf 群は stderr 経由でログファイルに書き、
# stdout は本物の gh を模した固定ファイル一覧のみに保つ。
{
  printf 'CALL'
  for arg in "$@"; do
    printf '\t%s' "$arg"
  done
  printf '\n'
} >> "${GH_STUB_LOG:-/dev/null}"
# 固定のファイル一覧を stdout に流す
cat <<'FILES'
package-lock.json
.github/dependabot.yml
src/index.ts
FILES
EOF
chmod +x "$STUB_DIR/gh"

# 1. 正常系: gh が呼ばれ、changed_files.txt 生成、$GITHUB_OUTPUT に count=N
GITHUB_OUTPUT_FILE="${WORK_DIR}/github_output"
: > "$GITHUB_OUTPUT_FILE"
GH_STUB_LOG="${WORK_DIR}/gh-args.log"
: > "$GH_STUB_LOG"

out="$(
  cd "$WORK_DIR" && \
  PATH="$STUB_DIR:$PATH" \
  GH_STUB_LOG="$GH_STUB_LOG" \
  GH_TOKEN=dummy \
  PR_NUMBER=42 \
  REPO=hirokimry/vibehawk \
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
  bash "$TARGET"
)" || {
  fail "正常系: スクリプトが非0終了 (out='$out')"
  echo "  gh args: $(cat "$GH_STUB_LOG" 2>/dev/null || echo none)"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
}

# changed_files.txt が生成されている
if [[ -f "${WORK_DIR}/changed_files.txt" ]]; then
  pass "changed_files.txt が cwd に生成される"
else
  fail "changed_files.txt が cwd に生成されていない"
fi

# 内容が gh スタブの出力と一致
expected_files="package-lock.json
.github/dependabot.yml
src/index.ts"
actual_files="$(cat "${WORK_DIR}/changed_files.txt")"
if [[ "$actual_files" == "$expected_files" ]]; then
  pass "changed_files.txt の内容が gh の出力と一致"
else
  fail "changed_files.txt の内容が想定と異なる: '$actual_files'"
fi

# $GITHUB_OUTPUT に count=3 が書き込まれている
if grep -Fxq "count=3" "$GITHUB_OUTPUT_FILE"; then
  pass "GITHUB_OUTPUT に count=3 が追記される"
else
  fail "GITHUB_OUTPUT に count=3 が追記されていない (内容: '$(cat "$GITHUB_OUTPUT_FILE")')"
fi

# gh が `api --paginate /repos/.../pulls/42/files --jq .[].filename` で呼ばれた
if grep -F "CALL	api	--paginate	/repos/hirokimry/vibehawk/pulls/42/files	--jq	.[].filename" "$GH_STUB_LOG" > /dev/null; then
  pass "gh api --paginate <endpoint> --jq <filter> が想定の引数で呼ばれる"
else
  fail "gh の呼び出し引数が想定と異なる: $(cat "$GH_STUB_LOG")"
fi

# stdout に「変更ファイル数: 3」が含まれている
if echo "$out" | grep -F "変更ファイル数: 3" > /dev/null; then
  pass "stdout に「変更ファイル数: 3」が出力される"
else
  fail "stdout に件数行が出ない: '$out'"
fi

# 2. 異常系: PR_NUMBER 未設定で exit 非 0
set +e
err_out="$(
  cd "$WORK_DIR" && \
  PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy \
  REPO=hirokimry/vibehawk \
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
  bash "$TARGET" 2>&1
)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -F "PR_NUMBER が必須です" > /dev/null; then
  pass "PR_NUMBER 未設定で exit 非0 + エラーメッセージ"
else
  fail "PR_NUMBER 未設定時の挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

# 3. 異常系: REPO 未設定で exit 非 0
set +e
err_out="$(
  cd "$WORK_DIR" && \
  PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy \
  PR_NUMBER=42 \
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
  bash "$TARGET" 2>&1
)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -F "REPO が必須です" > /dev/null; then
  pass "REPO 未設定で exit 非0 + エラーメッセージ"
else
  fail "REPO 未設定時の挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

# 4. 異常系: GITHUB_OUTPUT 未設定で exit 非 0
set +e
err_out="$(
  cd "$WORK_DIR" && \
  PATH="$STUB_DIR:$PATH" \
  GH_TOKEN=dummy \
  PR_NUMBER=42 \
  REPO=hirokimry/vibehawk \
  bash "$TARGET" 2>&1
)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -F "GITHUB_OUTPUT が必須です" > /dev/null; then
  pass "GITHUB_OUTPUT 未設定で exit 非0 + エラーメッセージ"
else
  fail "GITHUB_OUTPUT 未設定時の挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
