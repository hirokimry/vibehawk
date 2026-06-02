#!/usr/bin/env bash
# 用途: `@vibehawk review` コマンドの「差分なし」経路で vibehawk の verdict のみを
#       再評価する軽量パス（Issue #290、epic #289 子1）。前回レビュー以降にコミット差分が
#       無いとき（detect-review-diff.sh が diff_exists=false を出したとき）に呼ばれ、
#       Claude LLM レビューを一切実行せずに APPROVE / REQUEST_CHANGES を再 post する。
#
# 元は Issue #287（closed PR #288）で pull_request_review_thread トリガー用に作られたが、
# 同トリガーは GitHub Actions の on: で startup_failure になり実現不可と判明したため、
# epic #289 で `@vibehawk review` コマンド駆動（issue_comment トリガー）の差分なし経路へ移設した。
# 設計判断の WHY は docs/design-philosophy.md「@vibehawk コマンド体系の設計（epic #289 で確定）」参照。
#
# このスクリプトは Claude LLM レビュー（claude-code-action）を一切呼ばない（API コスト 0）。
# vibehawk 自身が author の review thread の未解決件数だけで APPROVE / REQUEST_CHANGES を決め、
# bot 名義で review を POST する。後続の post-status-check.sh が最新 review state から
# required check `vibehawk` の conclusion を再導出する。
#
# 設計の要点（WHY）:
#   - 自 Bot スレッドのみ数える: 全 thread で数えると vibehawk 未レビュー PR を誤 approve したり、
#     人間の未解決スレッドで無関係に REQUEST_CHANGES してしまう。CodeRabbit も「自身のコメント」
#     基準で approve する（公式 request_changes_workflow の定義）ため、自 Bot スレッド基準が忠実。
#   - 自 Bot スレッドが 0 件なら skip: vibehawk の管轄外。verdict を一切変更しない。
#   - body は APPROVE/REQUEST_CHANGES とも非空: post-status-check.sh は body 非空 review のみを
#     substantive として優先採用する。空 body の APPROVE を出すと過去の body 付き
#     CHANGES_REQUESTED が substantive-last のまま残り status check が failure に居座る。
#   - commit_id=HEAD_SHA: post-status-check.sh の HEAD_SHA 絞り込みと整合させる。
#   - 冪等: 直近の vibehawk review state と再判定結果が一致するなら POST しない
#     （再チェック連打での review コメント spam を防ぐ）。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
: "${OWNER:?OWNER must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

OWNER_NAME="${REPO%%/*}"
REPO_NAME="${REPO##*/}"

# reviewThreads 全ページ走査ヘルパーを source する（first:100 1 回読みの取りこぼし対策、CodeRabbit 指摘）。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/vibehawk-chat/lib-review-threads.sh
. "${SCRIPT_DIR}/lib-review-threads.sh"

# GitHub App login は小文字正規化（vibehawk-for-<owner>）。github.repository_owner は大文字
# 保持があり得る（例: "MyOrg"）ため両側を小文字化してから比較する（auto-resolve.sh と同じ、PR #193）。
normalized_owner="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
EXPECTED_LOGIN="vibehawk-for-${normalized_owner}"

# reviewThreads を author 付きで全ページ取得する（GraphQL author.login は [bot] サフィックスなし）。
THREADS_JSON="$(fetch_all_review_threads "${OWNER_NAME}" "${REPO_NAME}" "${PR_NUMBER}")"

# 自 Bot（vibehawk-for-<owner>）が author のスレッドだけを抽出する。author.login も小文字正規化する。
own_total="$(printf '%s' "$THREADS_JSON" | jq --arg login "$EXPECTED_LOGIN" '
  [ .data.repository.pullRequest.reviewThreads.nodes[]
    | select(((.comments.nodes[0].author.login // "") | ascii_downcase) == $login) ]
  | length')"

if [[ "$own_total" -eq 0 ]]; then
  echo "vibehawk: この PR に vibehawk 自身の review thread がありません（管轄外、skip、Issue #290）"
  echo "decided_event=SKIP" >> "$GITHUB_OUTPUT"
  echo "unresolved_count=0" >> "$GITHUB_OUTPUT"
  exit 0
fi

unresolved_count="$(printf '%s' "$THREADS_JSON" | jq --arg login "$EXPECTED_LOGIN" '
  [ .data.repository.pullRequest.reviewThreads.nodes[]
    | select(((.comments.nodes[0].author.login // "") | ascii_downcase) == $login)
    | select(.isResolved == false) ]
  | length')"

if [[ "$unresolved_count" -ge 1 ]]; then
  decided_event="REQUEST_CHANGES"
  review_body="🔴 vibehawk: 未解決の指摘が ${unresolved_count} 件あります。全て resolve すると自動で ✅ APPROVE に更新されます。"
else
  decided_event="APPROVE"
  review_body="✅ vibehawk: 指摘が全て resolve されたため、レビュー判定を APPROVE に更新しました。"
fi

echo "vibehawk: 自 Bot 未解決スレッド = ${unresolved_count} 件 → decided_event=${decided_event}（Issue #290）"
echo "decided_event=${decided_event}" >> "$GITHUB_OUTPUT"
echo "unresolved_count=${unresolved_count}" >> "$GITHUB_OUTPUT"

# 冪等: 直近の vibehawk substantive review state（HEAD_SHA, body 非空）を取得し、再判定結果と
# 一致するなら review POST を skip する。post-status-check.sh と同じ substantive 抽出ロジック。
# ページ横断集約は jq -s で行う（--paginate --jq はページ単位評価のため、cli/cli#1268）。
BOT_LOGIN="vibehawk-for-${normalized_owner}[bot]"
last_state="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate \
  | jq -r -s --arg bot "$BOT_LOGIN" --arg head "$HEAD_SHA" '
      [ .[][]
        | select(.user.login == $bot)
        | select(.commit_id == $head)
        | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED")
        | select((.body // "") | length > 0) ]
      | sort_by(.submitted_at) | last // {} | .state // ""')"

desired_state="APPROVED"
if [[ "$decided_event" == "REQUEST_CHANGES" ]]; then
  desired_state="CHANGES_REQUESTED"
fi

if [[ "$last_state" == "$desired_state" ]]; then
  echo "vibehawk: 直近 review state が既に ${desired_state} のため review POST を skip します（冪等、Issue #290）"
  exit 0
fi

# 変更があるときだけ bot 名義で review を POST する（-f で全フィールドを文字列として送る）。
gh api -X POST "repos/${REPO}/pulls/${PR_NUMBER}/reviews" \
  -f commit_id="${HEAD_SHA}" \
  -f event="${decided_event}" \
  -f body="${review_body}" > /dev/null

echo "vibehawk: review を ${decided_event} で POST しました（Issue #290）"
