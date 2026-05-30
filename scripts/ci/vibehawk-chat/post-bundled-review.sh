#!/usr/bin/env bash
# 用途: vibehawk-chat.yml の bundled review POST ステップ本体（Issue #135 / #177）
#
# Claude prompt はペイロードをファイルに書くだけで API を直接呼ばない設計。
# 本スクリプトが validate してから POST することでプロンプト注入経由の
# 任意 API 操作攻撃面を最小化する（Issue #121-C1 fix / セキュリティレビュー H-1 対応）。

set -euo pipefail

EVENT_FILE="/tmp/vibehawk-chat-review-event.txt"
BODY_FILE="/tmp/vibehawk-chat-review-body.txt"

# Claude がモード判定ミス等でペイロードを書いていない場合はスキップ
if [[ ! -f "$EVENT_FILE" ]] || [[ ! -f "$BODY_FILE" ]]; then
  echo "::warning::vibehawk chat: payload ファイル (event or body) が存在しないため bundled review POST をスキップ"
  exit 0
fi

# APPROVE / REQUEST_CHANGES 以外の event はプロンプト注入による意図しない値の埋め込み対策で弾く
event="$(head -1 "$EVENT_FILE" | tr -d '[:space:]')"
if [[ "$event" != "APPROVE" && "$event" != "REQUEST_CHANGES" ]]; then
  echo "::error::vibehawk chat: 不正な event 値: ${event}（APPROVE / REQUEST_CHANGES のみ許可）"
  exit 1
fi

# 空白文字のみは空とみなす（半角スペース・改行・タブを全て除去してから判定）
body="$(cat "$BODY_FILE")"
if [[ -z "${body//[[:space:]]/}" ]]; then
  echo "::error::vibehawk chat: REVIEW_BODY が空です"
  exit 1
fi

# commit_id を workflow 側で固定することで Claude による改ざんを防ぐ
jq -n \
  --arg event "$event" \
  --arg body "$body" \
  --arg commit_id "$HEAD_SHA" \
  '{event: $event, body: $body, commit_id: $commit_id}' \
  | gh api -X POST "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --input -
