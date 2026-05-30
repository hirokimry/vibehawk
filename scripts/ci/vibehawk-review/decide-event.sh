#!/usr/bin/env bash
# 用途: vibehawk-review.yml の event 決定ステップ本体（Issue #166 / #171）
#
# Claude の event フィールドは placeholder であり、本スクリプトが決定論的に算出した
# decided_event で post-bundled-review.sh が上書きしてから POST する（Issue #166）。
#
# 判定ルール（Issue #171: severity 不問・件数主軸 / Issue #270: 🧹 Nitpick 除外）:
#   1. unresolved >= 1 → REQUEST_CHANGES（最優先）
#   2. 新規 actionable inline 指摘（🧹 Nitpick 除外）の件数 >= 1 → REQUEST_CHANGES（severity 不問）
#   3. それ以外（actionable 0 件 = 🧹 Nitpick のみ含む） → APPROVE
#
# Issue #166 時点の旧ルールでは Critical/Major のみ REQUEST_CHANGES だったが、
# Issue #171 で「指摘する責務」と「修正対象判定の責務」を分離した
# （修正対象とするかは利用者の intent × severity マトリクスで判断、.claude/rules/review-handling.md）。
# MVV Value 3「指摘する、強制しない」の純粋実現。

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${STRUCTURED_OUTPUT:?STRUCTURED_OUTPUT must be set}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"

CLAUDE_OUT="${RUNNER_TEMP}/vibehawk-claude-output.json"
printf '%s' "$STRUCTURED_OUTPUT" > "$CLAUDE_OUT"

# `[]?` で null 許容にして comments が空配列でも 0 が返るようにする
# 旧実装（Issue #166）は severity 別に select() していたが、Issue #171 で全件カウントに変更した。
# Issue #270/#274: 🧹 Nitpick は非ブロッキング（インラインに出さず本文集約、CodeRabbit 準拠）のため
# event 判定の件数から除外する。actionable（Potential issue / Refactor）のみを数える。
# これにより nitpick のみのレビューは REQUEST_CHANGES にならず APPROVE になる。
new_comments_count="$(jq '[.comments[]? | select(.category != "🧹 Nitpick")] | length' "$CLAUDE_OUT")"
echo "vibehawk: 新規 actionable inline 指摘の件数 = ${new_comments_count}（🧹 Nitpick 除外、Issue #171/#270）"

# auto_resolve mutation 後の最新状態を GraphQL で取得する（auto_resolve → decide_event の順で実行）
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"
unresolved_count="$(gh api graphql \
  -f query='query($owner: String!, $name: String!, $pr: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $pr) { reviewThreads(first: 100) { nodes { isResolved } } } } }' \
  -F owner="${OWNER}" \
  -F name="${NAME}" \
  -F pr="${PR_NUMBER}" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false)) | length')"
echo "vibehawk: 未解決スレッド件数 = ${unresolved_count}"

if [[ "$unresolved_count" -ge 1 ]]; then
  decided_event="REQUEST_CHANGES"
  reason="unresolved >= 1"
elif [[ "$new_comments_count" -ge 1 ]]; then
  decided_event="REQUEST_CHANGES"
  reason="新規 actionable inline 指摘 >= 1（severity 不問・🧹 Nitpick 除外、Issue #171/#270）"
else
  decided_event="APPROVE"
  reason="unresolved == 0 かつ 新規 actionable inline 指摘 0 件（🧹 Nitpick のみは APPROVE）"
fi

echo "vibehawk: decided_event=${decided_event}（${reason}）"
echo "decided_event=${decided_event}" >> "$GITHUB_OUTPUT"
echo "unresolved_count=${unresolved_count}" >> "$GITHUB_OUTPUT"
echo "new_comments_count=${new_comments_count}" >> "$GITHUB_OUTPUT"
