#!/usr/bin/env bash
# 用途: PR の reviewThreads を GraphQL カーソルで全ページ走査するヘルパー（Issue #289、CodeRabbit 指摘対応）。
#       `reviewThreads(first: 100)` 1 回読みだと 101 件目以降を取りこぼし誤判定するため、
#       hasNextPage が false になるまでページングして全 thread を集約する。
#
# このファイルは source して使う（実行はしない）。
#   source "<dir>/lib-review-threads.sh"
#   threads_json="$(fetch_all_review_threads "$OWNER_NAME" "$REPO_NAME" "$PR_NUMBER")"
#
# 出力: 全ページ集約済みの `{data:{repository:{pullRequest:{reviewThreads:{nodes:[...]}}}}}`（既存呼出側の
# jq パス `.data.repository.pullRequest.reviewThreads.nodes[]` をそのまま使えるよう同一シェイプで返す）。
#
# 各 node のフィールド（id / isResolved / comments(first:1).author.login）は呼出側の用途に十分な共通集合。

# shellcheck disable=SC2120
fetch_all_review_threads() {
  local owner="$1" name="$2" pr="$3"
  local cursor="" all="[]" page nodes has_next end_cursor

  while :; do
    if [[ -z "$cursor" ]]; then
      page="$(gh api graphql \
        -f query='query($owner: String!, $name: String!, $pr: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $pr) { reviewThreads(first: 100) { pageInfo { hasNextPage endCursor } nodes { id isResolved comments(first: 1) { nodes { author { login } } } } } } } }' \
        -F owner="$owner" -F name="$name" -F pr="$pr")"
    else
      page="$(gh api graphql \
        -f query='query($owner: String!, $name: String!, $pr: Int!, $cursor: String!) { repository(owner: $owner, name: $name) { pullRequest(number: $pr) { reviewThreads(first: 100, after: $cursor) { pageInfo { hasNextPage endCursor } nodes { id isResolved comments(first: 1) { nodes { author { login } } } } } } } }' \
        -F owner="$owner" -F name="$name" -F pr="$pr" -F cursor="$cursor")"
    fi

    nodes="$(printf '%s' "$page" | jq -c '.data.repository.pullRequest.reviewThreads.nodes // []')"
    all="$(jq -c -n --argjson a "$all" --argjson b "${nodes:-[]}" '$a + $b')"

    has_next="$(printf '%s' "$page" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage // false')"
    end_cursor="$(printf '%s' "$page" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // ""')"
    if [[ "$has_next" != "true" || -z "$end_cursor" ]]; then
      break
    fi
    cursor="$end_cursor"
  done

  jq -c -n --argjson nodes "$all" '{data:{repository:{pullRequest:{reviewThreads:{nodes:$nodes}}}}}'
}
