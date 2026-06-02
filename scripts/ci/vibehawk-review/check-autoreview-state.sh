#!/usr/bin/env bash
# 用途: vibehawk-review.yml が PR の自動レビュー状態（active / paused / ignored）を読み取る
#       （Issue #295、epic #289 子6）。状態は vibehawk-for-<owner>[bot] 名義の issue コメントの
#       `<!-- vibehawk:autoreview=STATE -->` マーカーに保持される（set-autoreview-state.sh が書く）。
#
# paused / ignored の場合、vibehawk-review.yml は claude_review を skip し（自動レビュー停止）、
# status check は success「一時停止中」を post する（required check を緑に保ち merge をブロックしない）。
#
# 安全側の既定: マーカー不在 / 取得失敗 / 不正値は state=active（通常レビュー）に倒す。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${OWNER:?OWNER must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

normalized_owner="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
BOT_LOGIN="vibehawk-for-${normalized_owner}[bot]"

emit() { echo "state=$1" >> "$GITHUB_OUTPUT"; echo "vibehawk: autoreview 状態 = $1（Issue #295）"; }

comments="$(gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" --paginate 2>/dev/null || true)"
if [[ -z "$comments" ]]; then
  echo "::warning::vibehawk: issue コメント取得に失敗 → state=active（安全側、通常レビュー、Issue #295）"
  emit "active"
  exit 0
fi

# 自 Bot の最新マーカーコメント body を取得（作者フィルタ必須: 外部者の偽マーカーを無視、CISO 要件）。
marker_body="$(printf '%s' "$comments" | jq -r -s --arg bot "$BOT_LOGIN" '
  [ .[][]
    | select(.user.login == $bot)
    | select((.body // "") | contains("<!-- vibehawk:autoreview=")) ]
  | sort_by(.created_at) | last // {} | .body // ""')"

state="active"
if [[ -n "$marker_body" ]]; then
  # hex ではなく英小文字限定で抽出（インジェクション耐性）。
  extracted="$(printf '%s' "$marker_body" | grep -oE 'vibehawk:autoreview=[a-z]+' | sed 's/vibehawk:autoreview=//' | head -1 || true)"
  case "$extracted" in
    active|paused|ignored) state="$extracted" ;;
    *) state="active" ;;  # 不正値は安全側
  esac
fi

emit "$state"
