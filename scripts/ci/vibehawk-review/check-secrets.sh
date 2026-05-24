#!/usr/bin/env bash
# 用途: vibehawk-review.yml の secrets 検証ステップ本体
#
# 必須 3 secrets が未設定でも job は止めない（後段の placeholder 投稿 step が利用者に案内する）。

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

APP_ID="${APP_ID:-}"
PRIVATE_KEY="${PRIVATE_KEY:-}"
OAUTH_TOKEN="${OAUTH_TOKEN:-}"

missing=""
if [[ -z "$APP_ID" ]]; then missing="$missing VIBEHAWK_APP_ID"; fi
if [[ -z "$PRIVATE_KEY" ]]; then missing="$missing VIBEHAWK_PRIVATE_KEY"; fi
if [[ -z "$OAUTH_TOKEN" ]]; then missing="$missing CLAUDE_CODE_OAUTH_TOKEN"; fi

if [[ -n "$missing" ]]; then
  echo "ready=false" >> "$GITHUB_OUTPUT"
  echo "missing=${missing# }" >> "$GITHUB_OUTPUT"
  # `。`（U+3002）が直後にある場合、bash 一部 locale で変数名境界として認識されず
  # `$missing。` が set -u 下で "unbound variable" になるため ${missing} と波括弧を必須とする
  echo "::warning::vibehawk: 未設定 secret(s):${missing}。Settings → Secrets and variables → Actions で設定してください（README.md / docs/secrets-handling.md 参照）"
else
  echo "ready=true" >> "$GITHUB_OUTPUT"
fi
