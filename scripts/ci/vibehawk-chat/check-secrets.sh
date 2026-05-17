#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/check-secrets.sh
#
# vibehawk-chat.yml の `secrets 検証` step を切り出したスクリプト（Issue #177）。
# 3 つの secret（VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY / CLAUDE_CODE_OAUTH_TOKEN）の
# 設定有無を確認し、GITHUB_OUTPUT に `ready=true|false` および
# 未設定時の `missing=<スペース区切りリスト>` を書き出す。
#
# 入力（環境変数）:
#   APP_ID         -- ${{ secrets.VIBEHAWK_APP_ID }}
#   PRIVATE_KEY    -- ${{ secrets.VIBEHAWK_PRIVATE_KEY }}
#   OAUTH_TOKEN    -- ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
#   GITHUB_OUTPUT  -- GitHub Actions が自動付与する step output ファイルパス
#
# 出力:
#   stdout に `::warning::...` を吐く（未設定時のみ、GitHub Actions の warning 注釈）
#   GITHUB_OUTPUT に `ready=true|false`、`missing=<list>`（未設定時のみ）

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
