#!/usr/bin/env bash
# 用途: PR 本文に Issue 参照がない場合に fail させる（Issue #469 残 #5）
#
# vibecorp は Issue 経由起票必須運用のため、参照なし PR は通さない。
# Source of Truth: docs/conventional-commits.md, .claude/rules/intent-labels.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/log.sh
. "${SCRIPT_DIR}/../common/log.sh"

main() {
  : "${PR_NUMBER:?PR_NUMBER が必須です}"
  : "${REPO:?REPO が必須です}"

  local body
  body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body --jq '.body')
  if echo "$body" | grep -qiE '(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)[[:space:]]+#[0-9]+|(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)[[:space:]]+https?://[^[:space:]]+/issues/[0-9]+'; then
    log_info "PR 本文に Issue 参照が見つかりました"
    return 0
  fi
  gh pr comment "$PR_NUMBER" --repo "$REPO" \
    --body "⚠️ PR 本文に対応 Issue への参照（\`close #123\` / \`fixes #123\` / \`Refs #123\` など）が含まれていません。vibecorp は Issue 経由起票必須運用（Issue #469 残 #5）のため、PR 本文に Issue 参照を追加してから再 push してください。詳細は .claude/rules/intent-labels.md と docs/conventional-commits.md を参照。"
  return 1
}

main "$@"
