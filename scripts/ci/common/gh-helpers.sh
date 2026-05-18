#!/usr/bin/env bash
# scripts/ci/common/gh-helpers.sh
#
# gh CLI のラッパー関数群。
# `.claude/rules/shell.md` の「`gh api` のページネーション」規約に準拠する。
#
# - リスト系エンドポイント（issues/comments, issues/<n>/comments, pulls/<n>/comments,
#   reviews 等）は **必ず `--paginate` を付ける**
# - 未指定だと最初の 30 件のみ返り、以降が欠落するため
#
# 使用例:
#   source "$(dirname "$0")/../common/gh-helpers.sh"
#   gh_api_paginated "/repos/hirokimry/vibehawk/issues/175/comments"
#   gh_api_paginated "/repos/hirokimry/vibehawk/pulls/200/reviews" '.[] | .body'
#   gh_issue_field 175 title
#
# 注意:
# - 本ラッパーは認証情報を直接扱わない（gh CLI 側の `gh auth` に依存する）
# - エラー時の終了コードは gh CLI のそれをそのまま伝播する

# 多重 source 防止
if [[ -n "${VIBEHAWK_CI_GH_HELPERS_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
VIBEHAWK_CI_GH_HELPERS_LOADED=1

# 同ディレクトリの log.sh を読み込む（log_error を使うため）
# shellcheck source=./log.sh
. "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# gh api をページネーション付きで呼び出す。
#
# Usage: gh_api_paginated <endpoint> [jq_filter]
#
# - <endpoint>: 例 `/repos/hirokimry/vibehawk/issues/175/comments`
# - [jq_filter]: 省略可。指定時は `--jq <filter>` を渡す
#
# stdout に gh の出力を流す。エラー時は gh の exit code を返す。
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

# gh issue view から特定の JSON フィールドだけを抽出する。
#
# Usage: gh_issue_field <issue_number> <field_name>
#
# - <issue_number>: 例 175
# - <field_name>: 例 `title` / `body` / `state` / `labels`
#
# stdout に該当フィールドの値を JSON 形式で流す（`--jq '.<field>'`）。
gh_issue_field() {
  local issue_number="${1:-}"
  local field_name="${2:-}"

  if [[ -z "$issue_number" || -z "$field_name" ]]; then
    log_error "gh_issue_field: issue_number と field_name が必須です"
    return 2
  fi

  gh issue view "$issue_number" --json "$field_name" --jq ".${field_name}"
}
