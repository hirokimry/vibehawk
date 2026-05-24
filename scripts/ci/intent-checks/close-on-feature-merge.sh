#!/usr/bin/env bash
# 用途: feature/epic-* ブランチへのマージ時に PR 本文の close キーワードで Issue を自動 close する
#
# GitHub の自動 close は main へのマージ時にしか発火しないため（GitHub 仕様）、
# エピック運用（feature → main の二段階マージ）では feature マージ時に子 Issue が残存する。
# 本スクリプトはその制約を補完する（LLM 呼び出しなし・決定論的・課金ゼロ）。
#
# Refs #N / Related to #N は暴発防止のため対象外。すでに close 済みは冪等スキップ。
# 参照: https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/log.sh
. "${SCRIPT_DIR}/../common/log.sh"

main() {
  : "${REPO:?REPO が必須です}"
  : "${PR_NUMBER:?PR_NUMBER が必須です}"

  # Refs / Related to を除外して close キーワード + #N のみを抽出（暴発防止）
  local issues
  issues=$(
    printf '%s\n' "${PR_BODY:-}" \
      | grep -oiE '\b(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+#[0-9]+' \
      | grep -oE '[0-9]+' \
      | sort -u \
      || true
  )

  if [[ -z "$issues" ]]; then
    echo "::notice::PR 本文に close キーワード (Closes/Fixes/Resolves) #N が見つかりませんでした"
    return 0
  fi

  echo "対象 Issue 番号:"
  echo "$issues"

  # `for issue_num in $issues` は IFS 依存で壊れやすいため while read で安全に処理する
  local issue_num state
  while IFS= read -r issue_num; do
    [[ -z "$issue_num" ]] && continue
    state=$(gh issue view "$issue_num" --repo "$REPO" --json state --jq '.state')
    if [[ "$state" == "CLOSED" ]]; then
      echo "Issue #${issue_num} は既に close 済みのためスキップ"
      continue
    fi
    gh issue close "$issue_num" \
      --repo "$REPO" \
      --comment "✅ feature ブランチへのマージにより自動 close (PR #${PR_NUMBER})"
    echo "Issue #${issue_num} を close しました"
  done <<< "$issues"
}

main "$@"
