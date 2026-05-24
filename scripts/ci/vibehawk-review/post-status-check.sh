#!/usr/bin/env bash
# 用途: vibehawk-review.yml の status check POST ステップ本体（Issue #121-C1 fix）
#
# 最新の bundled review の state から conclusion を決定論的にマップして check-runs を POST する。
# branch protection の required check `vibehawk` を駆動する経路（merge gate の主軸）。

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
: "${OWNER:?OWNER must be set}"

BOT_LOGIN="vibehawk-for-${OWNER}[bot]"

# auto_resolve 後に空の COMMENTED review が副産物として追加されるため、単純な最後尾では
# neutral に倒れる（PR #129 観測）。APPROVED / CHANGES_REQUESTED かつ body 非空を優先取得し、
# 無ければ最新を fallback にする。
# また前回 run の別 commit review を拾わないよう HEAD_SHA で絞り込む（PR #153 Major 指摘対応）。
# ページ横断集約は jq -cs で行う（--paginate --jq はページ単位評価のため最新を正しく取れない、cli/cli#1268）。
substantive_review_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate \
  | jq -cs --arg bot "${BOT_LOGIN}" --arg head_sha "${HEAD_SHA}" '
      [ .[][]
        | select(.user.login == $bot)
        | select(.commit_id == $head_sha)
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
    | jq -cs --arg bot "${BOT_LOGIN}" --arg head_sha "${HEAD_SHA}" '
        [ .[][]
          | select(.user.login == $bot)
          | select(.commit_id == $head_sha)
        ]
        | sort_by(.submitted_at)
        | last // empty
      ')"
fi

# conclusion 導出（Issue #121-C1 / docs/specification.md）:
# APPROVED → success / CHANGES_REQUESTED → failure / その他 → neutral
if [[ -z "${review_json}" ]]; then
  conclusion="neutral"
  title="vibehawk: review 未投稿"
  summary="vibehawk review が見つかりません（claude-code-action の bundled POST が失敗している可能性があります）"
else
  state="$(echo "${review_json}" | jq -r '.state // ""')"
  body="$(echo "${review_json}" | jq -r '.body // ""')"

  case "${state}" in
    APPROVED)
      conclusion="success"
      title="vibehawk: APPROVED"
      ;;
    CHANGES_REQUESTED)
      conclusion="failure"
      title="vibehawk: CHANGES_REQUESTED"
      ;;
    *)
      conclusion="neutral"
      title="vibehawk: ${state}"
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
