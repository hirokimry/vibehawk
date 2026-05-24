#!/usr/bin/env bash
# 用途: vibehawk-chat.yml の secrets 検証ステップ本体（Issue #177）
#
# 必須 3 secrets（VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY / CLAUDE_CODE_OAUTH_TOKEN）の
# 設定有無を確認し、GITHUB_OUTPUT に ready=true|false を書き出す。

set -euo pipefail

missing=""
if [[ -z "${APP_ID:-}" ]]; then missing="$missing VIBEHAWK_APP_ID"; fi
if [[ -z "${PRIVATE_KEY:-}" ]]; then missing="$missing VIBEHAWK_PRIVATE_KEY"; fi
if [[ -z "${OAUTH_TOKEN:-}" ]]; then missing="$missing CLAUDE_CODE_OAUTH_TOKEN"; fi

if [[ -n "$missing" ]]; then
  echo "ready=false" >> "$GITHUB_OUTPUT"
  echo "missing=${missing# }" >> "$GITHUB_OUTPUT"
  echo "::warning::vibehawk chat: 未設定 secret(s):${missing}。レビュー workflow と同じ 3 secrets を設定してください（README.md / docs/secrets-handling.md 参照）"
else
  echo "ready=true" >> "$GITHUB_OUTPUT"
fi
