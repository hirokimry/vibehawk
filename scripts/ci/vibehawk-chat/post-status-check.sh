#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/post-status-check.sh
#
# vibehawk-chat.yml の `vibehawk status check を post（@vibehawk review 経路、
# Issue #135）` step を切り出したスクリプト（Issue #135 / Issue #177）。
# vibehawk-review.yml の `vibehawk status check を post` step と同等のロジック。
#
# Claude prompt から check-runs を呼ばない設計（Issue #121-C1 fix と同じ理由、
# claude-code-action permission model で deny されるため）。
#
# 入力（環境変数）:
#   GH_TOKEN       -- secrets.GITHUB_TOKEN（App permission 状態に依存しない、
#                     checks: write をデフォルト workflow token に付与する設計）
#   REPO           -- ${{ github.repository }}
#   PR_NUMBER      -- ${{ github.event.issue.number }}
#   OWNER          -- ${{ github.repository_owner }}

set -euo pipefail

BOT_LOGIN="vibehawk-for-${OWNER}[bot]"

# PR HEAD SHA を取得（check-runs API は head_sha 必須）
HEAD_SHA="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}" --jq '.head.sha')"

# vibehawk-review.yml と同じ substantive review filter で
# 直前の Claude セッションが投稿した最新 review を取得する。
# bundled POST 後に副産物の空 COMMENTED review が混入する可能性があるため、
# state == APPROVED / CHANGES_REQUESTED かつ body 非空で絞り込む。
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

# conclusion 導出表（vibehawk-review.yml と同じ）:
#   APPROVED         → success（merge OK）
#   CHANGES_REQUESTED → failure（merge ブロック）
#   COMMENTED 等その他 / review 未検出 → neutral（informational）
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

# check-runs API の output.summary は最大 65535 文字。安全側で 60000 字で切る。
summary="${summary:0:60000}"

gh api -X POST "repos/${REPO}/check-runs" \
  --field name="vibehawk" \
  --field head_sha="${HEAD_SHA}" \
  --field status="completed" \
  --field conclusion="${conclusion}" \
  --field "output[title]=${title}" \
  --field "output[summary]=${summary}"
