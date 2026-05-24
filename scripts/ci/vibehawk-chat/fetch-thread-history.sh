#!/usr/bin/env bash
# 用途: vibehawk-chat.yml のスレッド全コメント取得ステップ本体（Issue #11 / #177）
#
# Issue 本文 + 全コメントを時系列 JSON 配列に統合して /tmp に書き出す。
# 5 大方針 4「専用 DB なし」: スレッド自体が状態を保持するため外部 DB 不要。

set -euo pipefail

history_file="/tmp/vibehawk-thread-${ISSUE_NUMBER}.json"

# --paginate はページ単位で配列を出力するため、jq -s で全ページを 1 配列に slurp する
# （旧 .[0] + .[1] は 2 ページ固定で N ページに対応できなかった問題を修正、CodeRabbit PR #87）
gh api "repos/${REPO}/issues/${ISSUE_NUMBER}/comments" --paginate \
  --jq '.[] | {user: .user.login, created_at, body}' \
  | jq -s '.' \
  > "$history_file"

# Issue 本文を先頭に挿入することで会話の起点を含む時系列配列にする
issue_body="$(gh api "repos/${REPO}/issues/${ISSUE_NUMBER}" \
  --jq '{user: .user.login, created_at, body}')"

jq --argjson issue "$issue_body" '[$issue] + .' "$history_file" \
  > "${history_file}.combined"
mv "${history_file}.combined" "$history_file"

comment_count="$(jq 'length' "$history_file")"
echo "vibehawk chat: スレッド ${comment_count} コメント取得 → ${history_file}"

echo "history_file=$history_file" >> "$GITHUB_OUTPUT"
echo "comment_count=$comment_count" >> "$GITHUB_OUTPUT"
