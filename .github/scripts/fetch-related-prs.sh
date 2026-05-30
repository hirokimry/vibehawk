#!/usr/bin/env bash
# 用途: vibehawk Possibly related PRs セクション用のデータ取得（Issue #228）
#
# 入力（環境変数）:
#   REPO          owner/repo（必須）
#   PR_NUMBER     PR 番号（必須）
#   GITHUB_OUTPUT GitHub Actions step output ファイルパス（必須）
#
# 出力（GITHUB_OUTPUT に書き込み）:
#   related_prs_json   関連 PR の 1 行 JSON 配列 [{"number":N,"title":"..."}, ...] 最大 5 件
#
# 責務:
#   - 当該 PR タイトルからキーワードを抽出し search/issues API で類似 PR を検索する。
#   - 自身（current PR）と未マージ PR は除外。closed/merged PR のみ採用。
#   - rate limit / 失敗時は空配列 [] で degrade（sticky 側で「No related PRs found.」表示）。

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

# 機能: 当該 PR のタイトルを取得しキーワード抽出
pr_title="$(gh pr view "$PR_NUMBER" --repo "$REPO" --json title --jq '.title' 2>/dev/null || printf '')"

related_json='[]'

if [ -n "$pr_title" ]; then
  # シンプルな keyword 抽出: 英数字単語のうち 4 文字以上を最大 3 語取り出す（CC prefix 等の冒頭装飾は除外）
  keywords="$(printf '%s' "$pr_title" \
    | grep -oE '[A-Za-z][A-Za-z0-9_-]{3,}' \
    | grep -ivE '^(feat|fix|chore|docs|test|refactor|perf|build|ci|style|revert)$' \
    | head -3 \
    | tr '\n' ' ')"

  if [ -n "${keywords// /}" ]; then
    query="repo:${REPO} is:pr is:closed ${keywords}"
    raw="$(gh api "search/issues?q=$(printf '%s' "$query" | jq -sRr @uri)&per_page=5" 2>/dev/null \
      | jq -c --argjson cur "$PR_NUMBER" '[.items[]? | select(.number != $cur) | {number: .number, title: .title}]' 2>/dev/null || printf '[]')"
    if [ -n "$raw" ] && printf '%s' "$raw" | jq -e '.' > /dev/null 2>&1; then
      related_json="$raw"
    fi
  fi
fi

printf 'related_prs_json=%s\n' "$related_json" >> "$GITHUB_OUTPUT"
