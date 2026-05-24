#!/usr/bin/env bash
# scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh の単体テスト。
#
# 様々な changed_files.txt の入力に対し、is_skip 判定が想定通りであることを検証する。
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

TARGET="${REPO_ROOT}/scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh"

echo "=== scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh 単体テスト ==="

if [[ -f "$TARGET" ]]; then
  pass "classify-paths-ignore.sh が存在する"
else
  fail "classify-paths-ignore.sh が存在しない"
  exit 1
fi

if [[ -x "$TARGET" ]]; then
  pass "classify-paths-ignore.sh に実行権限が付いている"
else
  fail "classify-paths-ignore.sh に実行権限が付いていない"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# 注意: ローカル変数名は呼び出し側の変数名 (out / is_skip) と衝突しないよう
# _out / _is_skip プレフィックスを付ける（printf -v は dynamic scope で同名
# ローカルがあるとそちらに書き込むため）。
out=""
is_skip=""
run_classify() {
  local file_count="$1"
  local files_content="$2"
  local out_var="$3"
  local is_skip_var="$4"

  local changed_files="${WORK_DIR}/changed_files.txt"
  local github_output="${WORK_DIR}/github_output"
  printf '%s' "$files_content" > "$changed_files"
  : > "$github_output"

  local _out
  _out="$(
    FILE_COUNT="$file_count" \
    GITHUB_OUTPUT="$github_output" \
    CHANGED_FILES="$changed_files" \
    bash "$TARGET"
  )"
  local _is_skip
  _is_skip="$(grep -E '^is_skip=' "$github_output" | tail -1 | cut -d= -f2)"

  printf -v "$out_var" '%s' "$_out"
  printf -v "$is_skip_var" '%s' "$_is_skip"
}

run_classify 0 "" out is_skip
if [[ "$is_skip" == "false" ]]; then
  pass "file_count=0 で is_skip=false"
else
  fail "file_count=0 で is_skip=$is_skip（false 期待）"
fi

run_classify 1 "package-lock.json
" out is_skip
if [[ "$is_skip" == "true" ]]; then
  pass "package-lock.json 単独で is_skip=true"
else
  fail "package-lock.json 単独で is_skip=$is_skip（true 期待）"
fi

run_classify 4 "package-lock.json
yarn.lock
pnpm-lock.yaml
bun.lockb
" out is_skip
if [[ "$is_skip" == "true" ]]; then
  pass "lock 4 種全部で is_skip=true"
else
  fail "lock 4 種全部で is_skip=$is_skip（true 期待）"
fi

run_classify 1 ".github/dependabot.yml
" out is_skip
if [[ "$is_skip" == "true" ]]; then
  pass ".github/dependabot.yml 単独で is_skip=true"
else
  fail ".github/dependabot.yml 単独で is_skip=$is_skip（true 期待）"
fi

run_classify 2 "package-lock.json
.github/dependabot.yml
" out is_skip
if [[ "$is_skip" == "true" ]]; then
  pass "lock + dependabot 混在で is_skip=true"
else
  fail "lock + dependabot 混在で is_skip=$is_skip（true 期待）"
fi

run_classify 2 "package-lock.json
src/index.ts
" out is_skip
if [[ "$is_skip" == "false" ]]; then
  pass "package-lock.json + src/index.ts で is_skip=false"
else
  fail "package-lock.json + src/index.ts で is_skip=$is_skip（false 期待）"
fi

run_classify 1 "README.md
" out is_skip
if [[ "$is_skip" == "false" ]]; then
  pass "README.md 単独で is_skip=false（Issue #160 撤回後は **/*.md は対象外）"
else
  fail "README.md 単独で is_skip=$is_skip（false 期待）"
fi

run_classify 1 "CHANGELOG.md
" out is_skip
if [[ "$is_skip" == "false" ]]; then
  pass "CHANGELOG.md 単独で is_skip=false（Issue #160 撤回後は CHANGELOG* は対象外）"
else
  fail "CHANGELOG.md 単独で is_skip=$is_skip（false 期待）"
fi

run_classify 1 "package-lock.json
" out is_skip
if echo "$out" | grep -F "paths-ignore 全マッチ: true" > /dev/null; then
  pass "stdout に「paths-ignore 全マッチ: true」が出力される"
else
  fail "stdout に判定結果行が出ない: '$out'"
fi

# GitHub Actions runner では GITHUB_OUTPUT が親シェル env から子へ継承されるため、
# 単に「assign しない」だけでは不十分。env -u <VAR> で子 env から明示的に除去する。
# 参考: PR #184 の CI 失敗で発覚（macOS / Ubuntu の test-matrix）。

set +e
err_out="$(
  GITHUB_OUTPUT="${WORK_DIR}/github_output" \
  CHANGED_FILES="${WORK_DIR}/changed_files.txt" \
  env -u FILE_COUNT bash "$TARGET" 2>&1
)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -F "FILE_COUNT が必須です" > /dev/null; then
  pass "FILE_COUNT 未設定で exit 非0 + エラーメッセージ"
else
  fail "FILE_COUNT 未設定時の挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

set +e
err_out="$(
  FILE_COUNT=0 \
  CHANGED_FILES="${WORK_DIR}/changed_files.txt" \
  env -u GITHUB_OUTPUT bash "$TARGET" 2>&1
)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -F "GITHUB_OUTPUT が必須です" > /dev/null; then
  pass "GITHUB_OUTPUT 未設定で exit 非0 + エラーメッセージ"
else
  fail "GITHUB_OUTPUT 未設定時の挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

VIBEHAWK_REVIEW_YML="${REPO_ROOT}/templates/.github/workflows/vibehawk-review.yml"
if [[ -f "$VIBEHAWK_REVIEW_YML" ]]; then
  paths_ignore_count=$(awk '
    /^[[:space:]]+paths-ignore:/ { in_block = 1; next }
    in_block && /^[[:space:]]+[a-z_-]+:/ { exit }
    in_block && /^[[:space:]]+-[[:space:]]/ { count++ }
    END { print count }
  ' "$VIBEHAWK_REVIEW_YML")

  case_pattern_total=$(awk '
    /case[[:space:]]+"\$file"[[:space:]]+in/ { in_case = 1; next }
    in_case && /^[[:space:]]+esac/ { exit }
    in_case && /\)[[:space:]]+;;/ && !/^[[:space:]]+\*\)/ {
      line = $0
      sub(/\)[[:space:]]+;;.*/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      n = split(line, parts, "|")
      count += n
    }
    END { print count }
  ' "$TARGET")

  echo "  [info] vibehawk-review.yml paths-ignore: ${paths_ignore_count} 件 / classify-paths-ignore.sh case 文: ${case_pattern_total} pattern"

  if [[ "$paths_ignore_count" -eq "$case_pattern_total" ]]; then
    pass "paths-ignore 件数 (${paths_ignore_count}) と case 文パターン総数 (${case_pattern_total}) が一致（同期検証）"
  else
    fail "paths-ignore 件数 (${paths_ignore_count}) と case 文パターン総数 (${case_pattern_total}) が不一致（同期失敗）"
  fi
else
  fail "vibehawk-review.yml (${VIBEHAWK_REVIEW_YML}) が存在しないため同期検証不可"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
