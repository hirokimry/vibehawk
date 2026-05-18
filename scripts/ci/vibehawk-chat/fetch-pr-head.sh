#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/fetch-pr-head.sh
#
# vibehawk-chat.yml の `PR HEAD SHA を取得（@vibehawk review 経路、Issue #135）`
# step を切り出したスクリプト（Issue #135 / Issue #177）。`@vibehawk review`
# 経路で必要な PR の HEAD SHA を workflow step で取得し、GITHUB_OUTPUT に
# 書き出す。Claude prompt 内で `gh pr view` / `gh api` を呼ばずに済ませる
# ことで、プロンプト注入経由の API 操作攻撃面を最小化する
# （Issue #121-C1 fix と同じ思想）。
#
# 入力（環境変数）:
#   GH_TOKEN       -- App Installation Token（${{ steps.app-token.outputs.token }}）
#   REPO           -- ${{ github.repository }}
#   PR_NUMBER      -- ${{ github.event.issue.number }}
#   GITHUB_OUTPUT  -- GitHub Actions が自動付与する step output ファイルパス
#
# 出力:
#   GITHUB_OUTPUT: head_sha=<sha>

set -euo pipefail

HEAD_SHA="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}" --jq '.head.sha')"
echo "head_sha=$HEAD_SHA" >> "$GITHUB_OUTPUT"
