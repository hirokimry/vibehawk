#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/post-placeholder.sh
#
# vibehawk-chat.yml の `secrets 未設定時のプレースホルダ投稿` step を切り出した
# スクリプト（Issue #177）。3 secrets のいずれかが未設定のとき、Issue / PR
# スレッドに「設定してください」のプレースホルダコメントを投稿する。
#
# 入力（環境変数）:
#   GH_TOKEN       -- gh CLI が使うトークン（GITHUB_TOKEN を期待）
#   ISSUE_NUMBER   -- ${{ github.event.issue.number }}
#   MISSING        -- ${{ steps.check_secrets.outputs.missing }}（スペース区切りリスト）

set -euo pipefail

gh issue comment "$ISSUE_NUMBER" --body "🦅 vibehawk chat: 未設定 secret(s): \`$MISSING\` のため応答をスキップしました。3 secrets（VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY / CLAUDE_CODE_OAUTH_TOKEN）を Settings で設定してください。"
