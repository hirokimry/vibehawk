#!/usr/bin/env bash
# scripts/ci/vibehawk-review/decide-event.sh
#
# vibehawk-review.yml の "vibehawk event を決定（Issue #166 / #171）" ステップ（旧 L497
# インライン）の本体。
#
# claude-code-action が `outputs.structured_output` 経由で返した review JSON を
# 受け取り、`comments[]` の総件数（severity 不問、Issue #171）と GraphQL で取得する
# unresolved review thread 数から `decided_event`（APPROVE / REQUEST_CHANGES）を
# 決定論的に算出する。Claude の `event` フィールドは placeholder であり、後段の
# post-bundled-review.sh が本 step の決定値で JSON を上書きしてから POST する
# （Issue #166）。
#
# 判定ルール（Issue #171: severity 不問・件数主軸）:
#   1. unresolved >= 1 → REQUEST_CHANGES（最優先）
#   2. 新規 inline 指摘の総件数 >= 1 → REQUEST_CHANGES（severity 不問、新ルール）
#   3. それ以外 → APPROVE
#
# 旧ルール（Issue #166 時点）では 2 段目が「新規 Critical/Major あり → REQUEST_CHANGES」
# で Minor 以下は APPROVE 通過していた。Issue #171 で「指摘する責務」と「修正対象とする
# 判定の責務」を分離し、severity に依らず指摘が 1 件でもあれば REQUEST_CHANGES で
# 利用者に気付かせる設計に変更（MVV Value 3「指摘する、強制しない」の純粋実現）。
# 修正対象とするかは利用者プロジェクト側の intent × severity マトリクス
# （`.claude/rules/review-handling.md`）で判定する分担とする。
#
# 入力 env:
#   GH_TOKEN            — App installation token
#   REPO                — owner/repo
#   PR_NUMBER           — 対象 PR の番号
#   STRUCTURED_OUTPUT   — claude-code-action outputs.structured_output（JSON 文字列）
#   RUNNER_TEMP         — GitHub Actions runner の一時ディレクトリ
#
# 出力 GITHUB_OUTPUT:
#   decided_event=APPROVE|REQUEST_CHANGES
#   unresolved_count=<整数>
#   new_comments_count=<整数>  # Issue #171: severity 不問の総件数

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${STRUCTURED_OUTPUT:?STRUCTURED_OUTPUT must be set}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"

CLAUDE_OUT="${RUNNER_TEMP}/vibehawk-claude-output.json"
printf '%s' "$STRUCTURED_OUTPUT" > "$CLAUDE_OUT"

# 新規 inline 指摘の総件数（severity 不問、Issue #171）
# 指摘 0 件 (.comments == []) でも 0 が返るよう `[]?` で null 許容にしておく。
# 旧実装（Issue #166）では body 冒頭絵文字 (🔴 Critical / 🟠 Major) で
# select() フィルタしていたが、Issue #171 で severity に依らず全件数をカウントする
# 仕様に変更した（severity 別判別は不要、修正対象判定は利用者側の責務に分離）。
new_comments_count="$(jq '[.comments[]?] | length' "$CLAUDE_OUT")"
echo "vibehawk: 新規 inline 指摘の総件数 = ${new_comments_count}（severity 不問、Issue #171）"

# unresolved 数を GraphQL で取得（auto_resolve mutation 後の最新状態、Issue #166）
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"
unresolved_count="$(gh api graphql \
  -f query='query($owner: String!, $name: String!, $pr: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $pr) { reviewThreads(first: 100) { nodes { isResolved } } } } }' \
  -F owner="${OWNER}" \
  -F name="${NAME}" \
  -F pr="${PR_NUMBER}" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false)) | length')"
echo "vibehawk: 未解決スレッド件数 = ${unresolved_count}"

# 判定ルール（Issue #171: severity 不問・件数主軸）:
#   1. unresolved >= 1 → REQUEST_CHANGES（最優先）
#   2. 新規 inline 指摘の総件数 >= 1 → REQUEST_CHANGES（severity 不問）
#   3. それ以外 → APPROVE
if [[ "$unresolved_count" -ge 1 ]]; then
  decided_event="REQUEST_CHANGES"
  reason="unresolved >= 1"
elif [[ "$new_comments_count" -ge 1 ]]; then
  decided_event="REQUEST_CHANGES"
  reason="新規 inline 指摘 >= 1（severity 不問、Issue #171）"
else
  decided_event="APPROVE"
  reason="unresolved == 0 かつ 新規 inline 指摘 0 件"
fi

echo "vibehawk: decided_event=${decided_event}（${reason}）"
echo "decided_event=${decided_event}" >> "$GITHUB_OUTPUT"
echo "unresolved_count=${unresolved_count}" >> "$GITHUB_OUTPUT"
echo "new_comments_count=${new_comments_count}" >> "$GITHUB_OUTPUT"
