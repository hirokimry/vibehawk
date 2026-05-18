#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/fetch-thread-history.sh
#
# vibehawk-chat.yml の `スレッド全コメント取得` step を切り出したスクリプト
# （Issue #11 / Issue #177）。Issue / PR スレッドの全コメント + Issue 本文を
# 時系列で JSON 配列にまとめ、`/tmp/vibehawk-thread-${ISSUE_NUMBER}.json` に
# 出力する。5 大方針 4「専用 DB なし」: 状態は GitHub の thread 自体が保持。
#
# 入力（環境変数）:
#   GH_TOKEN       -- App Installation Token（${{ steps.app-token.outputs.token }}）
#   REPO           -- ${{ github.repository }}
#   ISSUE_NUMBER   -- ${{ github.event.issue.number }}
#   GITHUB_OUTPUT  -- GitHub Actions が自動付与する step output ファイルパス
#
# 出力:
#   ファイル: /tmp/vibehawk-thread-${ISSUE_NUMBER}.json
#   stdout に進捗ログ
#   GITHUB_OUTPUT: history_file=<path>, comment_count=<n>

set -euo pipefail

history_file="/tmp/vibehawk-thread-${ISSUE_NUMBER}.json"

# --paginate は各ページごとに JSON 配列を出力するため、
# --jq '.[] | {...}' で各要素を改行区切りで出力 → jq -s で 1 配列に slurp する
# （CodeRabbit PR #87 指摘: 旧 .[0] + .[1] は 2 ページ前提でページ数 N 任意に対応できない）
gh api "repos/${REPO}/issues/${ISSUE_NUMBER}/comments" --paginate \
  --jq '.[] | {user: .user.login, created_at, body}' \
  | jq -s '.' \
  > "$history_file"

# Issue 本文も含める（最初のコメントとして）
issue_body="$(gh api "repos/${REPO}/issues/${ISSUE_NUMBER}" \
  --jq '{user: .user.login, created_at, body}')"

# Issue 本文を最初に挿入: [issue_body, ...comments]
jq --argjson issue "$issue_body" '[$issue] + .' "$history_file" \
  > "${history_file}.combined"
mv "${history_file}.combined" "$history_file"

comment_count="$(jq 'length' "$history_file")"
echo "vibehawk chat: スレッド ${comment_count} コメント取得 → ${history_file}"

echo "history_file=$history_file" >> "$GITHUB_OUTPUT"
echo "comment_count=$comment_count" >> "$GITHUB_OUTPUT"
