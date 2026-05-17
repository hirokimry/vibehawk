#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/post-bundled-review.sh
#
# vibehawk-chat.yml の `vibehawk bundled review を post（@vibehawk review 経路、
# Issue #135）` step を切り出したスクリプト（Issue #135 / Issue #177）。
#
# Claude prompt は review event と body を payload ファイル 2 件に書くだけで
# API は呼ばない。本スクリプトが payload を validate して POST する
# （プロンプト注入経由の任意 API 操作攻撃面を最小化、Issue #121-C1 fix と
# 同じ思想、`@vibehawk review` 関連セキュリティレビュー H-1 への対応）。
#
# 入力（環境変数）:
#   GH_TOKEN       -- App Installation Token（${{ steps.app-token.outputs.token }}）
#                     vibehawk-for-<owner>[bot] 名義で review を投稿するため
#                     （以前の review との一貫性を保つ、Issue #121 bundled review API 設計に整合）
#   REPO           -- ${{ github.repository }}
#   PR_NUMBER      -- ${{ github.event.issue.number }}
#   HEAD_SHA       -- ${{ steps.pr_head.outputs.head_sha }}
#
# 入力（ファイル）:
#   /tmp/vibehawk-chat-review-event.txt -- "APPROVE" か "REQUEST_CHANGES" の 1 行
#   /tmp/vibehawk-chat-review-body.txt  -- REVIEW_BODY 全文

set -euo pipefail

EVENT_FILE="/tmp/vibehawk-chat-review-event.txt"
BODY_FILE="/tmp/vibehawk-chat-review-body.txt"

# Claude が payload を書いていない場合（モード判定ミス等）はスキップ
if [[ ! -f "$EVENT_FILE" ]] || [[ ! -f "$BODY_FILE" ]]; then
  echo "::warning::vibehawk chat: payload ファイル (event or body) が存在しないため bundled review POST をスキップ"
  exit 0
fi

# event の validate: APPROVE / REQUEST_CHANGES 限定（プロンプト注入で COMMENTED 等
# の予期しない event 値を埋め込まれることを防ぐ）。改行・余分な空白も除去。
event="$(head -1 "$EVENT_FILE" | tr -d '[:space:]')"
if [[ "$event" != "APPROVE" && "$event" != "REQUEST_CHANGES" ]]; then
  echo "::error::vibehawk chat: 不正な event 値: ${event}（APPROVE / REQUEST_CHANGES のみ許可）"
  exit 1
fi

# body の validate: 非空であること
body="$(cat "$BODY_FILE")"
if [[ -z "${body// /}" ]]; then
  echo "::error::vibehawk chat: REVIEW_BODY が空です"
  exit 1
fi

# commit_id は workflow step で fetch した HEAD_SHA を使う（Claude が改ざんできないよう
# workflow 側で固定）。bundled review POST は jq で payload を組み立てて --input - で渡す。
jq -n \
  --arg event "$event" \
  --arg body "$body" \
  --arg commit_id "$HEAD_SHA" \
  '{event: $event, body: $body, commit_id: $commit_id}' \
  | gh api -X POST "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --input -
