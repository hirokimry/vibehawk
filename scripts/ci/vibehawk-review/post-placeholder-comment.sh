#!/usr/bin/env bash
# scripts/ci/vibehawk-review/post-placeholder-comment.sh
#
# vibehawk-review.yml の "secrets 未設定時のプレースホルダ投稿" ステップ（旧 L89
# インライン）の本体。
#
# 必須 secrets が未設定で check-secrets.sh が `ready=false` を出力した場合に呼ばれ、
# 利用者向け案内コメントを PR に投稿する。
#
# 入力 env:
#   GH_TOKEN    — gh CLI が使う認証トークン（GitHub Actions のデフォルト GITHUB_TOKEN）
#   PR_NUMBER   — 対象 PR の番号
#   MISSING     — 未設定 secret 名のスペース区切りリスト

set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${MISSING:?MISSING must be set}"

# shellcheck disable=SC2016
# 上記 `gh pr comment` 文字列内のバッククォートはリテラルなコードフェンスを意図しており、
# Bash の command substitution ではない（マークダウン整形）。
gh pr comment "$PR_NUMBER" --body "🦅 vibehawk: 未設定 secret(s): \`$MISSING\` のためレビューをスキップしました。経路 2 必須化（Issue #61 確定）により以下 3 secrets を Settings → Secrets and variables → Actions で設定してください: \`VIBEHAWK_APP_ID\` / \`VIBEHAWK_PRIVATE_KEY\` / \`CLAUDE_CODE_OAUTH_TOKEN\`（詳細は README.md および docs/secrets-handling.md）。"
