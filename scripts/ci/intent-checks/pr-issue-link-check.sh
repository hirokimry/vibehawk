#!/usr/bin/env bash
# scripts/ci/intent-checks/pr-issue-link-check.sh
#
# PR 本文に対応 Issue の参照（Refs / close / closes / fix / fixes / resolve / resolves）が
# 含まれていない場合に fail させる。
# `.github/workflows/pr-issue-link-check.yml` から呼び出される。
#
# 必要な環境変数:
#   GH_TOKEN  : gh CLI 認証トークン（workflow 側で `env:` で渡す）
#   PR_NUMBER : 対象 PR 番号
#   REPO      : owner/repo 形式
#
# Issue #469 残 #5「Issue 番号取れない PR は fail（Issue 経由起票必須）」の実装。
# Source of Truth: docs/conventional-commits.md, .claude/rules/intent-labels.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/log.sh
. "${SCRIPT_DIR}/../common/log.sh"

main() {
  : "${PR_NUMBER:?PR_NUMBER が必須です}"
  : "${REPO:?REPO が必須です}"

  # PR 本文を取得し、Issue 参照キーワード（GitHub の auto-close keywords + Refs）を grep
  # close / closes / closed / fix / fixes / fixed / resolve / resolves / resolved / Refs (大小文字区別なし) + #数字
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
