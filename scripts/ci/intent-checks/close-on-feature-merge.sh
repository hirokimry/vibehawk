#!/usr/bin/env bash
# scripts/ci/intent-checks/close-on-feature-merge.sh
#
# feature/epic-* ブランチへの PR がマージされた時、PR 本文の close キーワード
# (Closes / Fixes / Resolves とそのバリエーション) で参照される Issue を自動 close する。
# `.github/workflows/close-on-feature-merge.yml` から呼び出される。
#
# 必要な環境変数:
#   GH_TOKEN  : gh CLI 認証トークン（workflow 側で `env:` で渡す）
#   REPO      : owner/repo 形式
#   PR_NUMBER : マージされた PR 番号
#   PR_BODY   : マージされた PR の本文
#
# GitHub の自動 close 仕様は default branch (main) へのマージ時のみ発火するため、
# vibecorp のエピック運用 (feature → main の二段階マージ) では子 PR が
# feature ブランチへマージされた時点で子 Issue が自動 close されない。
# 本スクリプトはその制約を回避するためのもの。
#
# 設計:
#   - LLM 呼び出し一切なし (決定論的 / 課金ゼロ)
#   - 抽出対象は Closes / Fixes / Resolves とそのバリエーション (close[sd]? / fix(es|ed)? / resolve[sd]?)
#   - Refs #N / Related to #N は対象外 (暴発防止)
#   - 同一リポジトリの Issue のみ対象 (cross-repo 非対応)
#   - すでに close 済みの Issue はスキップ (冪等性)
#
# 参照:
#   - GitHub 公式: https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue#linking-a-pull-request-to-an-issue-using-a-keyword
#   - 配布判断の根拠: docs/design-philosophy.md「統合問題は配布先のデフォルト CI で担保する」

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/log.sh
. "${SCRIPT_DIR}/../common/log.sh"

main() {
  : "${REPO:?REPO が必須です}"
  : "${PR_NUMBER:?PR_NUMBER が必須です}"

  # close キーワード + 空白 + #N の形式のみを抽出。
  # 抽出対象: close / closes / closed / fix / fixes / fixed / resolve / resolves / resolved
  # 対象外:   refs / related to (暴発防止)
  # GNU grep (ubuntu-latest) の -oiE で正規表現マッチを行う。
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

  # IFS 依存を排除するため while read で 1 行ずつ処理する。
  # for issue_num in $issues は unquoted word splitting で IFS 設定に依存するため避ける。
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
