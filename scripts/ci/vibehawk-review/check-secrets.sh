#!/usr/bin/env bash
# scripts/ci/vibehawk-review/check-secrets.sh
#
# vibehawk-review.yml の "secrets 検証" ステップ（旧 L70 インライン）の本体。
#
# 経路 2（GitHub App + claude-code-action）の必須 secrets 3 種が設定されているかを
# 確認し、`$GITHUB_OUTPUT` に `ready=true|false` と未設定の場合の `missing=<list>` を
# 書き出す。未設定があれば `::warning::` を 1 件出して呼び出し側に通知する（job 自体
# は止めない — placeholder 投稿 step が後段で利用者に案内するため）。
#
# 入力 env:
#   APP_ID         — VIBEHAWK_APP_ID
#   PRIVATE_KEY    — VIBEHAWK_PRIVATE_KEY
#   OAUTH_TOKEN    — CLAUDE_CODE_OAUTH_TOKEN
#   GITHUB_OUTPUT  — GitHub Actions が用意する出力先ファイル
#
# 出力 GITHUB_OUTPUT:
#   ready=true|false
#   missing=<space-separated secret names>  （ready=false のときのみ）

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
  # `${missing}` を必ず波括弧付きで参照する。直後の `。`（U+3002）は bash の
  # 一部 locale で variable name 境界として正しく認識されず、`set -u` 下で
  # `$missing。` が "unbound variable" になるため（旧 yaml の `run: |` は
  # set -u 無効だったので顕在化していなかった）。
  echo "::warning::vibehawk: 未設定 secret(s):${missing}。Settings → Secrets and variables → Actions で設定してください（README.md / docs/secrets-handling.md 参照）"
else
  echo "ready=true" >> "$GITHUB_OUTPUT"
fi
