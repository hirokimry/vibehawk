#!/usr/bin/env bash
# 用途: vibehawk-chat.yml の status check POST ステップ本体（Issue #135 / #177）
#
# Claude prompt から check-runs を呼ばない設計（Issue #121-C1 fix と同じ思想、
# claude-code-action の permission model で deny されるため workflow 側で実行する）。

set -euo pipefail

BOT_LOGIN="vibehawk-for-${OWNER}[bot]"

HEAD_SHA="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}" --jq '.head.sha')"

# bundled POST 後に副産物の空 COMMENTED review が混入するため、
# APPROVED / CHANGES_REQUESTED かつ body 非空で substantive review を優先取得する。
substantive_review_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate \
  | jq -cs --arg bot "${BOT_LOGIN}" '
      [ .[][]
        | select(.user.login == $bot)
        | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED")
        | select((.body // "") | length > 0)
      ]
      | sort_by(.submitted_at)
      | last // empty
    ')"

if [[ -n "${substantive_review_json}" ]]; then
  review_json="${substantive_review_json}"
else
  review_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate \
    | jq -cs --arg bot "${BOT_LOGIN}" '
        [ .[][]
          | select(.user.login == $bot)
        ]
        | sort_by(.submitted_at)
        | last // empty
      ')"
fi

# conclusion 導出表（vibehawk-review.yml と同じ仕様）:
# APPROVED → success / CHANGES_REQUESTED → failure / その他 → neutral
if [[ -z "${review_json}" ]]; then
  conclusion="neutral"
  title="vibehawk: review 未投稿（@vibehawk review）"
  summary="@vibehawk review で再レビューが要求されましたが、bundled POST が確認できませんでした。chat workflow ログを確認してください。"
else
  state="$(echo "${review_json}" | jq -r '.state // ""')"
  body="$(echo "${review_json}" | jq -r '.body // ""')"

  case "${state}" in
    APPROVED)
      conclusion="success"
      title="vibehawk: APPROVED（@vibehawk review）"
      ;;
    CHANGES_REQUESTED)
      conclusion="failure"
      title="vibehawk: CHANGES_REQUESTED（@vibehawk review）"
      ;;
    *)
      conclusion="neutral"
      title="vibehawk: ${state}（@vibehawk review）"
      ;;
  esac
  summary="${body}"
fi

# check-runs API の output.summary 上限 65535 文字に対して安全マージンを取る
summary="${summary:0:60000}"

gh api -X POST "repos/${REPO}/check-runs" \
  --field name="vibehawk" \
  --field head_sha="${HEAD_SHA}" \
  --field status="completed" \
  --field conclusion="${conclusion}" \
  --field "output[title]=${title}" \
  --field "output[summary]=${summary}"
