#!/usr/bin/env bash
# 用途: `@vibehawk resolve` コマンドで vibehawk 自身（vibehawk-for-<owner>）が author の
#       未解決 review thread を一括 resolved 化する（Issue #292、epic #289 子3）。
#       auto-resolve.sh（自動解決、Issue #167）の手動コマンド版。
#
# auto-resolve.sh との違い:
#   - auto-resolve.sh は Claude の STRUCTURED_OUTPUT（resolved_thread_ids）を入力にする。
#   - 本スクリプトは LLM 非依存で、自前で「自 Bot かつ未解決」のスレッドを全件収集する。
#
# 二重防御（auto-resolve.sh から踏襲。自前収集でも維持する理由 = 多層防御）:
#   1. case/esac glob で node_id 許可文字（Base64 + URL-safe Base64）のみ通す。
#      自前収集では GitHub GraphQL の正規値が入るが、API レスポンス改ざん・将来の
#      リファクタで外部入力が混入した場合の安全網として残す。
#   2. mutation 直前に GraphQL から author.login を再取得し vibehawk bot を再確認する。
#      他者・他 Bot のスレッドを誤 resolve しない（収集ロジックのバグへの保険）。
#
# resolve 後の verdict 更新は後続 step（re-evaluate-verdict.sh）が行う。resolveReviewThread は
# スレッドを reviewThreads から消さず isResolved=true にするだけなので、re-evaluate-verdict.sh の
# own_total は >0 のまま・unresolved は 0 になり APPROVE に再評価される（自 Bot スレッドが元から
# 0 件の PR では re-evaluate-verdict.sh が SKIP し verdict を変えない＝未レビュー PR を誤 approve しない）。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${OWNER:?OWNER must be set}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

# GitHub App login は小文字正規化（vibehawk-for-<owner>）。github.repository_owner は大文字
# 保持があり得る（例: "MyOrg"）ため両側を小文字化してから比較する（auto-resolve.sh と同じ、PR #193）。
normalized_owner="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
EXPECTED_LOGIN="vibehawk-for-${normalized_owner}"

# 全 reviewThread を {id, isResolved, author.login} で取得する（auto-resolve.sh と同形・同上限）。
# GraphQL author.login は [bot] サフィックスなしで返る（REST API とは異なる GitHub GraphQL 仕様）。
THREADS_JSON="$(gh api graphql \
  -f query='query($owner: String!, $name: String!, $pr: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $pr) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 1) { nodes { author { login } } } } } } } }' \
  -F owner="${REPO%%/*}" \
  -F name="${REPO##*/}" \
  -F pr="${PR_NUMBER}")"

# first: 100 上限の truncation 警告: 100 件返ってきたら 101 件目以降を取りこぼしている可能性がある。
# 手動 resolve は「全件解決」が意図のため、上限到達を可観測にする（auto-resolve.sh は LLM 選択リスト
# 入力のため上限の意味が異なるが、本スクリプトは全件収集なので明示警告する）。
total_nodes="$(printf '%s' "$THREADS_JSON" | jq '.data.repository.pullRequest.reviewThreads.nodes | length')"
if [[ "$total_nodes" -ge 100 ]]; then
  echo "::warning::vibehawk: reviewThreads が上限 100 件に達しました。101 件目以降の未解決スレッドは今回の resolve 対象外の可能性があります（Issue #292）"
fi

# 自 Bot かつ未解決のスレッド id を収集する（author.login も小文字正規化して比較）。
own_unresolved_ids=()
while IFS= read -r line; do
  line="${line%$'\r'}"
  [[ -n "$line" ]] && own_unresolved_ids+=("$line")
done < <(printf '%s' "$THREADS_JSON" | jq -r --arg login "$EXPECTED_LOGIN" '
  .data.repository.pullRequest.reviewThreads.nodes[]
  | select(.isResolved == false)
  | select(((.comments.nodes[0].author.login // "") | ascii_downcase) == $login)
  | .id')

resolved_count=0
skipped_count=0
failed_count=0

# bash 3.2 + set -u では空配列の "${arr[@]}" 展開が unbound エラーになるため、
# 要素ありの時だけループする（macOS bash 3.2 互換、shell.md）。
for tid in ${own_unresolved_ids[@]+"${own_unresolved_ids[@]}"}; do
  # 第1防御: node_id 許可文字チェック（Base64 / URL-safe Base64）。OS 非依存の case/esac glob。
  case "$tid" in
    '' | *[!A-Za-z0-9+/=_-]* )
      echo "::warning::vibehawk: thread id が GitHub node_id 形式に一致しません（skip）"
      skipped_count=$((skipped_count + 1))
      continue
      ;;
  esac

  # 第2防御: mutation 直前に author.login を再取得し vibehawk bot を再確認する。
  author="$(printf '%s' "$THREADS_JSON" | jq -r --arg id "$tid" \
    '.data.repository.pullRequest.reviewThreads.nodes[] | select(.id == $id) | (.comments.nodes[0].author.login // "")')"
  author="${author%$'\r'}"
  normalized_author="$(printf '%s' "$author" | tr '[:upper:]' '[:lower:]')"
  if [[ "$normalized_author" != "$EXPECTED_LOGIN" ]]; then
    echo "::warning::vibehawk: thread $tid の投稿者は ${author}（${EXPECTED_LOGIN} ではない）、誤 resolve 防止のため skip"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  # 個別失敗は warning + skip で後続を止めない（auto-resolve.sh と同じパターン）。
  if gh api graphql \
       -f query='mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { isResolved } } }' \
       -F id="$tid" > /dev/null; then
    resolved_count=$((resolved_count + 1))
  else
    echo "::warning::vibehawk: thread $tid の resolveReviewThread mutation に失敗しました（次の thread に進みます）"
    failed_count=$((failed_count + 1))
  fi
done

echo "vibehawk: resolve 完了（resolved=${resolved_count}, skipped=${skipped_count}, failed=${failed_count}）"
echo "resolved_count=${resolved_count}" >> "$GITHUB_OUTPUT"

# 確認コメントを投稿する。本文に @vibehawk を含めない（無限ループ防止）。
if [[ "$resolved_count" -gt 0 ]]; then
  comment_body="🦅 vibehawk: 自身の指摘 ${resolved_count} 件を resolve しました。"
else
  comment_body="🦅 vibehawk: resolve 対象の未解決指摘はありませんでした。"
fi
gh issue comment "$ISSUE_NUMBER" --body "$comment_body"
