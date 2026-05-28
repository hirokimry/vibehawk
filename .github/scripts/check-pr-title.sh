#!/usr/bin/env bash
# 用途: vibehawk Pre-merge checks の Title check（Issue #229）
#
# 入力（環境変数）:
#   PR_TITLE        PR タイトル（必須）
#   GITHUB_OUTPUT   GitHub Actions step output ファイルパス（必須）
#
# 出力（GITHUB_OUTPUT に書き込み）:
#   title_check_status        passed / failed
#   title_check_explanation   判定理由（1 文）
#
# 判定基準:
#   PR タイトルが「<絵文字> <prefix>: <subject>」形式に従うかを正規表現で機械判定。
#   CC prefix 11 種 (feat/fix/perf/refactor/style/docs/test/ci/chore/build/revert) に加え、
#   vibehawk の release-epic skill が生成する `release:`（リリース PR）も許容する。
#   （release を欠くと vibehawk 自身のリリース PR タイトルが title_check で failed になる、PR #235）

set -euo pipefail

: "${PR_TITLE:?PR_TITLE must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

# 機能: prefix + コロンを検出（絵文字は任意の Unicode を許容するため正規表現は緩く）
if printf '%s' "$PR_TITLE" | grep -qE '^(.+ )?(feat|fix|perf|refactor|style|docs|test|ci|chore|build|revert|release)(\(.+\))?:[[:space:]]'; then
  status="passed"
  explanation="PR タイトルが Conventional Commits 形式 (絵文字 + CC prefix + コロン) に従っている"
else
  status="failed"
  explanation="PR タイトルが Conventional Commits 形式 (例: '✨ feat: ...') に従っていない"
fi

{
  printf 'title_check_status=%s\n' "$status"
  printf 'title_check_explanation=%s\n' "$explanation"
} >> "$GITHUB_OUTPUT"
