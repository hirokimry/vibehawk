#!/usr/bin/env bash
# scripts/ci/intent-checks/intent-label-issue-check.sh
#
# Issue にも intent/* ラベル 1 つだけが付与されていることを機械的に強制する。
# `.github/workflows/intent-label-issue-check.yml` から呼び出される。
#
# 必要な環境変数:
#   GH_TOKEN     : gh CLI 認証トークン（workflow 側で `env:` で渡す）
#   ISSUE_NUMBER : 対象 Issue 番号
#   REPO         : owner/repo 形式
#
# Issue #469 残 #3「intent ラベル不在 Issue/PR は CI/hook で必須化（fail）」の Issue 側実装。
# Source of Truth: docs/conventional-commits.md, .claude/rules/intent-labels.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/log.sh
. "${SCRIPT_DIR}/../common/log.sh"

main() {
  : "${ISSUE_NUMBER:?ISSUE_NUMBER が必須です}"
  : "${REPO:?REPO が必須です}"

  # intent/* ラベルの全体数と許可ラベル 7 種のカウントを別々に取得
  # 全体数 != 許可数 → 未知の intent/* (intent/unknown 等) が混在 → fail
  local allowed='["intent/feature","intent/bugfix","intent/performance","intent/security","intent/refactor","intent/infra","intent/docs"]'
  local counts
  counts=$(gh api "repos/${REPO}/issues/${ISSUE_NUMBER}/labels" \
    | jq --argjson allowed "$allowed" '{
        total_intent: ([.[] | .name | select(startswith("intent/"))] | length),
        allowed_intent: ([.[] | .name | select(IN($allowed[]))] | length)
      }')
  local total_intent allowed_intent unknown_intent
  total_intent=$(jq -r '.total_intent' <<< "$counts")
  allowed_intent=$(jq -r '.allowed_intent' <<< "$counts")
  unknown_intent=$(( total_intent - allowed_intent ))

  if [[ "$unknown_intent" -gt 0 ]]; then
    gh issue comment "$ISSUE_NUMBER" --repo "$REPO" \
      --body "⚠️ 許可されていない intent/* ラベルが含まれています。1 Issue 1 intent ルールに従い、許可 7 種（intent/feature, intent/bugfix, intent/performance, intent/security, intent/refactor, intent/infra, intent/docs）から 1 つだけ付与してください。"
    return 1
  fi
  if [[ "$allowed_intent" -eq 0 ]]; then
    gh issue comment "$ISSUE_NUMBER" --repo "$REPO" \
      --body "⚠️ intent/* ラベルが付与されていません（許可 7 種のうち 1 つを付ける必要があります）。1 Issue 1 intent ルール（intent/feature, intent/bugfix, intent/performance, intent/security, intent/refactor, intent/infra, intent/docs から 1 つ）に従い、ラベルを 1 つ付与してください。詳細は .claude/rules/intent-labels.md を参照。"
    return 1
  fi
  if [[ "$allowed_intent" -gt 1 ]]; then
    gh issue comment "$ISSUE_NUMBER" --repo "$REPO" \
      --body "⚠️ 複数の intent ラベル（許可 7 種のうち）が付与されています。1 Issue 1 intent ルールに従い、ラベルを 1 つに修正してください。"
    return 1
  fi
}

main "$@"
