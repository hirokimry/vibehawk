#!/usr/bin/env bash
# 用途: `@vibehawk pause` / `resume` / `ignore` で PR の自動レビュー状態を GitHub 上に保持する
#       （Issue #295、epic #289 子6）。外部 DB を持たず（5 大方針 4）、状態は vibehawk-for-<owner>[bot]
#       名義の issue コメントに `<!-- vibehawk:autoreview=STATE -->` マーカーとして 1 個 upsert する。
#
# 観察の ON/OFF 制御であり MVV Value 2 の範囲内（コード・PR メタデータ＝ラベル等は触らない）。
# pause 中でも手動 `@vibehawk review` は動く（review 経路は本状態を読まない）。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${REPO:?REPO must be set}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER must be set}"
: "${OWNER:?OWNER must be set}"
: "${COMMENT_BODY:?COMMENT_BODY must be set}"

# COMMENT_BODY は contains 判定にのみ使う（eval しない＝インジェクションなし）。
# 判定順: resume を pause/ignore より優先（解除を取りこぼさない）。
if [[ "$COMMENT_BODY" == *"@vibehawk resume"* ]]; then
  state="active"
  human="▶️ 自動レビューを再開しました（active）。"
elif [[ "$COMMENT_BODY" == *"@vibehawk pause"* ]]; then
  state="paused"
  human="⏸️ この PR の自動レビューを一時停止しました（paused）。手動の \`@vibehawk review\` は引き続き利用できます。\`@vibehawk resume\` で再開します。"
elif [[ "$COMMENT_BODY" == *"@vibehawk ignore"* ]]; then
  state="ignored"
  human="🚫 この PR を自動レビュー対象外にしました（ignored）。手動の \`@vibehawk review\` は引き続き利用できます。\`@vibehawk resume\` で再開します。"
else
  echo "vibehawk: pause/resume/ignore のいずれも検出できませんでした（skip、Issue #295）"
  exit 0
fi

normalized_owner="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
BOT_LOGIN="vibehawk-for-${normalized_owner}[bot]"
MARKER_PREFIX="<!-- vibehawk:autoreview="

body="$(printf '%s\n%s' "🦅 vibehawk: ${human}" "<!-- vibehawk:autoreview=${state} -->")"

# 既存の自 Bot autoreview マーカーコメントを find→PATCH、無ければ POST（post-sticky-comment.sh と同パターン）。
existing="$(gh api "repos/${REPO}/issues/${ISSUE_NUMBER}/comments" --paginate 2>/dev/null || true)"
existing_id=""
if [[ -n "$existing" ]]; then
  existing_id="$(printf '%s' "$existing" | jq -r -s --arg bot "$BOT_LOGIN" --arg marker "$MARKER_PREFIX" '
    [ .[][]
      | select(.user.login == $bot)
      | select((.body // "") | contains($marker)) ]
    | sort_by(.created_at) | last // {} | .id // ""')"
fi

if [[ -n "$existing_id" ]]; then
  jq -nc --arg body "$body" '{body: $body}' \
    | gh api -X PATCH "repos/${REPO}/issues/comments/${existing_id}" --input - > /dev/null
  echo "vibehawk: autoreview 状態を ${state} に更新しました（既存マーカー PATCH、Issue #295）"
else
  jq -nc --arg body "$body" '{body: $body}' \
    | gh api -X POST "repos/${REPO}/issues/${ISSUE_NUMBER}/comments" --input - > /dev/null
  echo "vibehawk: autoreview 状態を ${state} に設定しました（新規マーカー POST、Issue #295）"
fi
