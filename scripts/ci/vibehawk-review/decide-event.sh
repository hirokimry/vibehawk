#!/usr/bin/env bash
# scripts/ci/vibehawk-review/decide-event.sh
#
# vibehawk-review.yml の "vibehawk event を決定（Issue #166）" ステップ（旧 L497
# インライン）の本体。
#
# claude-code-action が `outputs.structured_output` 経由で返した review JSON を
# 受け取り、`comments[]` の severity 分布（🔴 Critical / 🟠 Major の件数）と GraphQL
# で取得する unresolved review thread 数から `decided_event`（APPROVE /
# REQUEST_CHANGES）を決定論的に算出する。Claude の `event` フィールドは placeholder
# であり、後段の post-bundled-review.sh が本 step の決定値で JSON を上書きしてから
# POST する（Issue #166）。
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
#   critical_major_count=<整数>

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${STRUCTURED_OUTPUT:?STRUCTURED_OUTPUT must be set}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"

CLAUDE_OUT="${RUNNER_TEMP}/vibehawk-claude-output.json"
printf '%s' "$STRUCTURED_OUTPUT" > "$CLAUDE_OUT"

# severity 分布カウント（comments[].body 冒頭絵文字から、Issue #166）
# 🔴 = U+1F534 Critical / 🟠 = U+1F7E0 Major。jq は UTF-8 文字列を unicode で扱うため
# startswith() がそのまま動く。指摘 0 件 (.comments == []) でも 0 が返るよう `[]?` で
# null 許容にしておく。
critical_major_count="$(jq '[.comments[]? | select(.body | startswith("🔴") or startswith("🟠"))] | length' "$CLAUDE_OUT")"
echo "vibehawk: 新規 inline 指摘の Critical/Major 件数 = ${critical_major_count}"

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

# 判定ルール（旧 prompt 内ロジックを 1:1 移植、Issue #166）:
#   1. unresolved >= 1 → REQUEST_CHANGES（最優先）
#   2. 新規 Critical/Major あり → REQUEST_CHANGES
#   3. それ以外 → APPROVE
if [[ "$unresolved_count" -ge 1 ]]; then
  decided_event="REQUEST_CHANGES"
  reason="unresolved >= 1"
elif [[ "$critical_major_count" -ge 1 ]]; then
  decided_event="REQUEST_CHANGES"
  reason="新規 Critical/Major あり"
else
  decided_event="APPROVE"
  reason="unresolved == 0 かつ 新規 Critical/Major なし"
fi

echo "vibehawk: decided_event=${decided_event}（${reason}）"
echo "decided_event=${decided_event}" >> "$GITHUB_OUTPUT"
echo "unresolved_count=${unresolved_count}" >> "$GITHUB_OUTPUT"
echo "critical_major_count=${critical_major_count}" >> "$GITHUB_OUTPUT"
