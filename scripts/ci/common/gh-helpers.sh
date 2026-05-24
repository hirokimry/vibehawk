#!/usr/bin/env bash
# 用途: gh CLI の paginate 付きラッパー関数群（shell.md「gh api のページネーション」準拠）
#
# リスト系エンドポイントは 30 件上限を超えると欠落するため、常に --paginate を付ける。
#
# 使用例:
#   source "$(dirname "$0")/../common/gh-helpers.sh"
#   gh_api_paginated "/repos/hirokimry/vibehawk/issues/175/comments"
#   gh_api_paginated "/repos/hirokimry/vibehawk/pulls/200/reviews" '.[] | .body'
#   gh_issue_field 175 title

# 多重 source 防止
if [[ -n "${VIBEHAWK_CI_GH_HELPERS_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
VIBEHAWK_CI_GH_HELPERS_LOADED=1

# shellcheck source=./log.sh
. "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# 機能: --paginate 付きで gh api を呼び出す（30 件打ち切り回避）
gh_api_paginated() {
  local endpoint="${1:-}"
  local jq_filter="${2:-}"

  if [[ -z "$endpoint" ]]; then
    log_error "gh_api_paginated: endpoint が必須です"
    return 2
  fi

  if [[ -n "$jq_filter" ]]; then
    gh api --paginate "$endpoint" --jq "$jq_filter"
  else
    gh api --paginate "$endpoint"
  fi
}

# 機能: gh issue view から指定フィールドの値を取り出す
gh_issue_field() {
  local issue_number="${1:-}"
  local field_name="${2:-}"

  if [[ -z "$issue_number" || -z "$field_name" ]]; then
    log_error "gh_issue_field: issue_number と field_name が必須です"
    return 2
  fi

  gh issue view "$issue_number" --json "$field_name" --jq ".${field_name}"
}
