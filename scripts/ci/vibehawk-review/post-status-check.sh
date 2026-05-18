#!/usr/bin/env bash
# scripts/ci/vibehawk-review/post-status-check.sh
#
# vibehawk-review.yml の "vibehawk status check を post（Issue #121-C1 fix）"
# ステップ（旧 L631 インライン）の本体。
#
# vibehawk bot が直前に投稿した最新の bundled review を取得し、その `state`
# （APPROVED / CHANGES_REQUESTED / その他）から check-runs API の conclusion
# (success / failure / neutral) に決定論的にマップして post する。branch protection
# の required status check `vibehawk` を駆動する経路（vibehawk merge gate の主軸）。
#
# 入力 env:
#   GH_TOKEN    — デフォルト GITHUB_TOKEN（checks: write 権限が付与済み）
#   REPO        — owner/repo
#   PR_NUMBER   — 対象 PR の番号
#   HEAD_SHA    — PR HEAD の commit SHA
#   OWNER       — リポジトリオーナー名

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
: "${OWNER:?OWNER must be set}"

BOT_LOGIN="vibehawk-for-${OWNER}[bot]"

# 直前の Claude セッションが投稿した vibehawk の最新 review を取得する。
# bundled review POST 後に auto_resolve thread 解決で空の COMMENTED review が
# 副産物として追加されるため、単純な「最後尾」では空 COMMENTED を拾い conclusion が
# neutral に倒れる（Issue #121 追加修正、PR #129 観測）。substantive な review
# （APPROVED / CHANGES_REQUESTED かつ body 非空）を優先取得し、無ければ素の最新を
# fallback に使う。
# `gh api --paginate` の生 JSON を `jq -cs` で slurp 集約してから一括フィルタする
# （prev_summary ステップと同じパターン、ページ横断集約の必要性は cli/cli#1268 / #10459）。
#
# PR #153 (Issue #152) CodeRabbit Major 指摘対応: 現在の HEAD_SHA に紐づく review のみを
# 抽出する。`.commit_id` で絞り込むことで、前回 run で投稿された別 commit の review を
# 誤って拾って status check に stale な conclusion が載るのを防ぐ。GitHub Reviews API
# では review オブジェクトに `commit_id` が含まれる。
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

# conclusion 導出表（Issue #121-C1、docs/specification.md status check 仕様）:
#   APPROVED         → success（merge OK）
#   CHANGES_REQUESTED → failure（merge ブロック）
#   COMMENTED 等その他 / review 未検出 → neutral（informational）
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

# check-runs API の output.summary は最大 65535 文字。安全側で 60000 字で切る。
summary="${summary:0:60000}"

gh api -X POST "repos/${REPO}/check-runs" \
  --field name="vibehawk" \
  --field head_sha="${HEAD_SHA}" \
  --field status="completed" \
  --field conclusion="${conclusion}" \
  --field "output[title]=${title}" \
  --field "output[summary]=${summary}"
