#!/usr/bin/env bash
# 用途: vibehawk-chat.yml の PR HEAD SHA 取得ステップ本体（Issue #135 / #177）
#
# Claude prompt 内で gh api を呼ばせずに workflow step で事前取得することで、
# プロンプト注入経由の API 操作攻撃面を最小化する（Issue #121-C1 fix と同じ思想）。

set -euo pipefail

HEAD_SHA="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}" --jq '.head.sha')"
echo "head_sha=$HEAD_SHA" >> "$GITHUB_OUTPUT"
