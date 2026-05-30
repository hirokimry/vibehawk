#!/usr/bin/env bash
# 用途: vibehawk PR sticky walkthrough コメントの upsert（Issue #219）
#
# 入力（環境変数）:
#   GH_TOKEN   GitHub auth token（App Installation Token か default GITHUB_TOKEN、いずれも issues: write 範疇）
#   REPO       owner/repo（必須）
#   PR_NUMBER  PR 番号（必須）
#   OWNER      owner（必須、bot 名義フィルタ用）
#
# 入力（標準入力）:
#   sticky body markdown（build-sticky-body.sh の出力をパイプ）
#
# 処理:
#   1. issues/comments を --paginate で取得し jq -cs でページ横断集約
#      （find-prev-summary.sh 同パターン、cli/cli#1268 / #10459 対策）
#   2. bot 名義（vibehawk-for-${OWNER}[bot] or github-actions[bot]）+ 先頭マーカー一致で filter
#   3. 件数で分岐: 0 → POST / 1 → PATCH / 2+ → 古い方 DELETE + 最新 PATCH（race condition 対策）
#
# エラーハンドリング: gh api 失敗（401 / 403 / rate limit）は warning ログ出力で exit 0。
# merge gate を倒さない（`vibehawk` status check は別ステップで post される）。

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${OWNER:?OWNER must be set}"

STICKY_BODY=$(cat)
if [ -z "$STICKY_BODY" ]; then
  echo "::error::vibehawk sticky: 標準入力 (body) が空です。"
  exit 1
fi

BOT_LOGIN_APP="vibehawk-for-${OWNER}[bot]"
BOT_LOGIN_DEFAULT="github-actions[bot]"

EXISTING=$(gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" --paginate) || {
  echo "::warning::vibehawk sticky: issues/comments 取得失敗 → skip"
  exit 0
}

MATCHES=$(printf '%s' "$EXISTING" | jq -cs --arg bot1 "$BOT_LOGIN_APP" --arg bot2 "$BOT_LOGIN_DEFAULT" '
  [ .[][]
    | select(.user.login == $bot1 or .user.login == $bot2)
    | select((.body // "") | startswith("<!-- This is an auto-generated comment: sticky-summary by vibehawk -->"))
    | select((.body // "") | contains("<!-- vibehawk:sticky -->"))
  ]
  | sort_by(.created_at)
')

COUNT=$(printf '%s' "$MATCHES" | jq 'length')

upsert_request() {
  local method="$1"
  local endpoint="$2"
  jq -nc --arg body "$STICKY_BODY" '{body: $body}' | gh api -X "$method" "$endpoint" --input -
}

RESPONSE=""
case "$COUNT" in
  0)
    echo "vibehawk sticky: 既存 0 件 → POST 新規"
    RESPONSE=$(upsert_request POST "repos/${REPO}/issues/${PR_NUMBER}/comments") || {
      echo "::warning::vibehawk sticky: POST 失敗 → skip"
      exit 0
    }
    ;;
  1)
    ID=$(printf '%s' "$MATCHES" | jq -r '.[0].id')
    echo "vibehawk sticky: 既存 1 件 (id=${ID}) → PATCH 更新"
    RESPONSE=$(upsert_request PATCH "repos/${REPO}/issues/comments/${ID}") || {
      echo "::warning::vibehawk sticky: PATCH 失敗 → skip"
      exit 0
    }
    ;;
  *)
    LATEST_ID=$(printf '%s' "$MATCHES" | jq -r '.[-1].id')
    OLDER_IDS=$(printf '%s' "$MATCHES" | jq -r '.[:-1] | .[].id')
    OLDER_COUNT=$(printf '%s\n' "$OLDER_IDS" | grep -c . || echo 0)
    echo "vibehawk sticky: 既存 ${COUNT} 件（race condition）→ 古い ${OLDER_COUNT} 件 DELETE + 最新 (id=${LATEST_ID}) PATCH"
    while IFS= read -r OID; do
      [ -z "$OID" ] && continue
      gh api -X DELETE "repos/${REPO}/issues/comments/${OID}" >/dev/null || \
        echo "::warning::vibehawk sticky: 重複 sticky DELETE 失敗 (id=${OID})"
    done <<< "$OLDER_IDS"
    RESPONSE=$(upsert_request PATCH "repos/${REPO}/issues/comments/${LATEST_ID}") || {
      echo "::warning::vibehawk sticky: PATCH 失敗 → skip"
      exit 0
    }
    ;;
esac

STICKY_URL=$(printf '%s' "$RESPONSE" | jq -r '.html_url // empty')
echo "vibehawk sticky: 完了 (${STICKY_URL})"

if [ -n "${GITHUB_OUTPUT:-}" ] && [ -n "$STICKY_URL" ]; then
  echo "sticky_url=${STICKY_URL}" >> "$GITHUB_OUTPUT"
fi
