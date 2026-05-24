#!/usr/bin/env bash
# 用途: PR 作成時に対応 Issue の intent/* ラベルを自動継承する（Issue #487 / #469）
#
# 「1 PR 1 intent 厳守」（.claude/rules/intent-labels.md）の補助。
# 複数 Issue の intent が分岐している場合はエラー停止して利用者に判断を促す。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/log.sh
. "${SCRIPT_DIR}/../common/log.sh"

main() {
  : "${PR_NUMBER:?PR_NUMBER が必須です}"
  : "${REPO:?REPO が必須です}"

  local body
  body=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body --jq '.body')

  # `#数字` 形式と URL 形式の両方に対応（/vibecorp:pr の --ref オプション運用と整合）
  local issue_numbers
  issue_numbers=$(echo "$body" | grep -oiE '(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)[[:space:]]+#[0-9]+|(close[sd]?|fix(es|ed)?|resolve[sd]?|refs?)[[:space:]]+https?://[^[:space:]]+/issues/[0-9]+' \
    | grep -oE '[0-9]+$' \
    | sort -u || true)

  if [[ -z "$issue_numbers" ]]; then
    log_info "対応 Issue が PR 本文から検出できませんでした（キーワード不在）。継承スキップ。"
    log_info "別ジョブの pr-issue-link-check が PR 本文の Issue 参照必須化を担当します。"
    return 0
  fi

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

  local unique_intents
  unique_intents=$(printf '%s\n' "$inherited" | sed '/^$/d' | sort -u)
  local unique_count
  unique_count=$(printf '%s\n' "$unique_intents" | sed '/^$/d' | wc -l | tr -d ' ')

  # 継承可能 Issue が存在しても、未設定 Issue への警告を黙殺しないよう独立して実行する
  if [[ -n "$missing_intent_issues" ]]; then
    local existing_warning
    existing_warning=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json comments --jq '[.comments[] | select(.body | startswith("⚠️ 対応 Issue"))] | length' 2>/dev/null || echo "0")
    if [[ "${existing_warning:-0}" -eq 0 ]]; then
      gh pr comment "$PR_NUMBER" --repo "$REPO" \
        --body "⚠️ 対応 Issue（${missing_intent_issues}）に intent/* ラベルが付与されていません。Issue 側で intent ラベルを 1 つ付与してから PR を再 push してください。詳細は \`.claude/rules/intent-labels.md\` を参照。"
    fi
  fi

  # 複数 intent を全件付与すると後続の intent-label-issue-check が fail するため、ここで先に止める（.claude/rules/intent-labels.md）
  if [[ "$unique_count" -gt 1 ]]; then
    local existing_split
    existing_split=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json comments --jq '[.comments[] | select(.body | startswith("❌ 対応 Issue 群の intent が分岐"))] | length' 2>/dev/null || echo "0")
    if [[ "${existing_split:-0}" -eq 0 ]]; then
      local intent_list
      intent_list=$(printf '%s' "$unique_intents" | tr '\n' ' ')
      gh pr comment "$PR_NUMBER" --repo "$REPO" \
        --body "❌ 対応 Issue 群の intent が分岐しています（候補: ${intent_list}）。1 PR 1 intent 厳守（\`.claude/rules/intent-labels.md\`）のため、Issue を分割するか、対応する 1 つの intent に揃えてから再 push してください。"
    fi
    log_error "複数 intent (${unique_count}) を検出。1 PR 1 intent 厳守のため継承を中止"
    return 1
  fi

  if [[ -z "$unique_intents" ]]; then
    log_info "Issue 側に intent ラベルがないため継承不可。"
    return 0
  fi

  # 重複付与防止のため既存ラベルを確認してからコピーする
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
