#!/usr/bin/env bash
# 用途: vibehawk-review.yml の secrets 未設定時プレースホルダ投稿ステップ本体

set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${MISSING:?MISSING must be set}"

# shellcheck disable=SC2016
# 上記 `gh pr comment` 文字列内のバッククォートはリテラルなコードフェンスを意図しており、
# Bash の command substitution ではない（マークダウン整形）。
gh pr comment "$PR_NUMBER" --body "🦅 vibehawk: 未設定 secret(s): \`$MISSING\` のためレビューをスキップしました。経路 2 必須化（Issue #61 確定）により以下 3 secrets を Settings → Secrets and variables → Actions で設定してください: \`VIBEHAWK_APP_ID\` / \`VIBEHAWK_PRIVATE_KEY\` / \`CLAUDE_CODE_OAUTH_TOKEN\`（詳細は README.md および docs/secrets-handling.md）。"
