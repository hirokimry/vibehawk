#!/usr/bin/env bash
# 用途: `@vibehawk summary` コマンドで PR の sticky walkthrough コメントを LLM 非依存で再生成する
#       （Issue #293、epic #289 子4）。既存の vibehawk インライン指摘（= 既存の検出結果）と
#       PR メタ情報（commits / files）から sticky を組み立て、既存 sticky を再 upsert する。
#
# LLM 再レビューはしない（差分なし時も軽量）。walkthrough_narrative（LLM 散文）と changes_table は
# 再構築しないため Walkthrough セクションは非出力になるが、severity 集計・主要指摘（既存インライン由来）と
# Recent review info（commits / files）は復元される。
#
# 既存スクリプトを流用する（完了条件 3）:
#   build-sticky-body.sh（STRUCTURED_OUTPUT + メタから sticky 本文生成）→ post-sticky-comment.sh（upsert）。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
: "${OWNER:?OWNER must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW_DIR="${SCRIPT_DIR}/../vibehawk-review"

normalized_owner="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
BOT_LOGIN="vibehawk-for-${normalized_owner}[bot]"

# 既存の vibehawk インライン review コメントを取得し {comments:[{path,line,body}]} を再構築する。
# build-sticky-body.sh はこの comments[] から severity 集計・主要指摘を生成する。
# 取得失敗時は空 comments にフォールバックする（merge gate を倒さない。sticky は最小構成で再生成）。
inline_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/comments" --paginate 2>/dev/null || true)"
if [[ -n "$inline_json" ]]; then
  STRUCTURED_OUTPUT="$(printf '%s' "$inline_json" | jq -cs --arg bot "$BOT_LOGIN" '
    { comments: [ .[][]
        | select(.user.login == $bot)
        | { path: (.path // ""), line: (.line // .original_line // 0), body: (.body // "") } ] }')"
else
  echo "::warning::vibehawk summary: インライン review コメント取得に失敗。空の検出結果で sticky を再生成します（Issue #293）"
  # コマンド置換で組み立てる（リテラル代入は SC2089/SC2090 を誘発するため）
  STRUCTURED_OUTPUT="$(jq -nc '{comments: []}')"
fi

# PR メタ情報（Recent review info 用、取得失敗は空フォールバック）
COMMITS_JSON="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/commits" --paginate 2>/dev/null \
  | jq -cs '[ .[][] | {sha: .sha} ]' 2>/dev/null || printf '')"
FILES_SELECTED_JSON="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate 2>/dev/null \
  | jq -cs '[ .[][] | .filename ]' 2>/dev/null || printf '')"

# DECIDED_EVENT を直近の vibehawk substantive review state から導出する。
# 渡さないと build-sticky-body が COMMENT にデフォルトし、sticky state marker の verdict が
# 上書きされてしまう（@vibehawk summary は verdict を変えない＝現状の判定を保持する）。
last_state="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate 2>/dev/null \
  | jq -r -s --arg bot "$BOT_LOGIN" '
      [ .[][]
        | select(.user.login == $bot)
        | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED")
        | select((.body // "") | length > 0) ]
      | sort_by(.submitted_at) | last // {} | .state // ""' 2>/dev/null || printf '')"
case "$last_state" in
  APPROVED)          DECIDED_EVENT="APPROVE" ;;
  CHANGES_REQUESTED) DECIDED_EVENT="REQUEST_CHANGES" ;;
  *)                 DECIDED_EVENT="COMMENT" ;;
esac

echo "vibehawk summary: sticky を再生成します（verdict=${DECIDED_EVENT}, HEAD=${HEAD_SHA}、LLM 非実行、Issue #293）"

export STRUCTURED_OUTPUT DECIDED_EVENT HEAD_SHA PR_NUMBER REPO COMMITS_JSON FILES_SELECTED_JSON
bash "${REVIEW_DIR}/build-sticky-body.sh" \
  | OWNER="$OWNER" REPO="$REPO" PR_NUMBER="$PR_NUMBER" GH_TOKEN="$GH_TOKEN" \
      bash "${REVIEW_DIR}/post-sticky-comment.sh"
