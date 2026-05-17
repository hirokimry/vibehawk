#!/usr/bin/env bash
# scripts/ci/intent-checks/pr-intent-inherit.sh
#
# PR 作成時に対応 Issue の intent/* ラベルを自動的に PR にコピーする。
# `.github/workflows/pr-intent-inherit.yml` から呼び出される。
#
# 必要な環境変数:
#   GH_TOKEN  : gh CLI 認証トークン（workflow 側で `env:` で渡す）
#   PR_NUMBER : 対象 PR 番号
#   REPO      : owner/repo 形式
#
# 設計:
#   - 対応 Issue を PR 本文の close/fix/resolve/ref キーワード経由で抽出する
#   - 各 Issue の intent/* ラベル（ホワイトリスト 7 種）を PR にコピーする
#   - 既存 intent ラベルがあれば重複付与しない
#   - Issue 側に intent ラベル不在なら警告コメント（重複防止付き）を投稿する
#
# Issue #487 / Issue #469 で確定した「1 PR 1 intent 厳守」運用の補助。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/log.sh
. "${SCRIPT_DIR}/../common/log.sh"

main() {
  : "${PR_NUMBER:?PR_NUMBER が必須です}"
  : "${REPO:?REPO が必須です}"

  # PR 本文から Issue 番号を抽出
  # 対応キーワード: close / closes / closed / fix / fixes / fixed / resolve / resolves / resolved / ref / refs（大小文字区別なし）
  local body
  body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body --jq '.body')

  # 「キーワード #数字」と「キーワード URL/issues/数字」の両方をマッチ
  # ref / refs 両対応（/vibecorp:pr の --ref オプション運用と整合）
  local issue_numbers
  issue_numbers=$(echo "$body" | grep -oiE '(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)[[:space:]]+#[0-9]+|(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)[[:space:]]+https?://[^[:space:]]+/issues/[0-9]+' \
    | grep -oE '[0-9]+$' \
    | sort -u || true)

  if [[ -z "$issue_numbers" ]]; then
    log_info "対応 Issue が PR 本文から検出できませんでした（キーワード不在）。継承スキップ。"
    log_info "別ジョブの pr-issue-link-check が PR 本文の Issue 参照必須化を担当します。"
    return 0
  fi

  # 各 Issue から intent/* ラベルを取得
  local allowed='["intent/feature","intent/bugfix","intent/performance","intent/security","intent/refactor","intent/infra","intent/docs"]'
  local inherited=""
  local missing_intent_issues=""
  local issue_num
  for issue_num in $issue_numbers; do
    local issue_intents
    issue_intents=$(gh api "repos/${REPO}/issues/${issue_num}/labels" \
      | jq --argjson allowed "$allowed" -r '[.[] | .name | select(IN($allowed[]))][]' 2>/dev/null || true)
    if [[ -z "$issue_intents" ]]; then
      missing_intent_issues="${missing_intent_issues} #${issue_num}"
      continue
    fi
    local intent
    for intent in $issue_intents; do
      # 重複排除のため改行区切りで蓄積
      inherited="${inherited}${intent}"$'\n'
    done
  done

  # 重複排除して PR にラベル追加（ホワイトリスト 7 種のみ）
  local unique_intents
  unique_intents=$(echo -n "$inherited" | sort -u)
  if [[ -z "$unique_intents" ]]; then
    if [[ -n "$missing_intent_issues" ]]; then
      # 同じ警告コメントが既に投稿されていればスキップ（synchronize イベントの push ごと重複防止）
      local existing_warning
      existing_warning=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json comments --jq '[.comments[] | select(.body | startswith("⚠️ 対応 Issue"))] | length' 2>/dev/null || echo "0")
      if [[ "${existing_warning:-0}" -eq 0 ]]; then
        gh pr comment "$PR_NUMBER" --repo "$REPO" \
          --body "⚠️ 対応 Issue（${missing_intent_issues}）に intent/* ラベルが付与されていません。Issue 側で intent ラベルを 1 つ付与してから PR を再 push してください。詳細は \`.claude/rules/intent-labels.md\` を参照。"
      fi
    fi
    log_info "Issue 側に intent ラベルがないため継承不可。"
    return 0
  fi

  # 既に PR に同じ intent ラベルがある場合はスキップ（重複付与防止）
  local existing
  existing=$(gh api "repos/${REPO}/issues/${PR_NUMBER}/labels" --jq '[.[] | .name | select(startswith("intent/"))] | join("\n")' 2>/dev/null || true)
  local intent
  while IFS= read -r intent; do
    [[ -z "$intent" ]] && continue
    if echo "$existing" | grep -qFx -- "$intent"; then
      log_info "PR に既に '${intent}' あり、スキップ"
      continue
    fi
    gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label "$intent"
    log_info "PR に '${intent}' を継承付与"
  done <<<"$unique_intents"
}

main "$@"
