#!/usr/bin/env bash
# 用途: vibehawk-review.yml の前回サマリ取得・インクリメンタルレビュー範囲決定ステップ本体（Issue #8）
#
# Issue #121 で bundled review API に移行したため、サマリは review body に埋め込まれる。
# <!-- vibehawk:summary --> と <!-- vibehawk:sha=<hex> --> マーカーで前回 SHA を特定し、
# force push / rebase の場合は完全再レビューに切り替える。

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${OWNER:?OWNER must be set}"
: "${BASE_REF:?BASE_REF must be set}"

BOT_LOGIN="vibehawk-for-${OWNER}[bot]"

# `gh api --paginate --jq` はページ単位で jq を評価するためページ横断で最新を取れない。
# 生 JSON を jq -cs でページ横断集約してから一括フィルタする（cli/cli#1268 / #10459）。
# 旧 issue comment 形式（Issue #121 以前）は <!-- vibehawk:summary --> マーカーがないため自然に除外される。
summary_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate \
  | jq -cs --arg bot "${BOT_LOGIN}" '
      [ .[][]
        | select(.user.login == $bot)
        | select((.body // "") | contains("<!-- vibehawk:summary -->"))
      ]
      | sort_by(.submitted_at)
      | last // empty
    ')"

if [[ -z "${summary_json}" ]]; then
  echo "vibehawk: 前回サマリ未検出 → 初回レビュー"
  echo "incremental=false" >> "$GITHUB_OUTPUT"
  echo "comment_id=" >> "$GITHUB_OUTPUT"
  echo "prev_sha=" >> "$GITHUB_OUTPUT"
  echo "review_range=" >> "$GITHUB_OUTPUT"
  exit 0
fi

# comment_id は後方互換のため GITHUB_OUTPUT に残すが prompt 側では使わない
# （PATCH 不可・edit 経路は Issue #121 bundled review 移行で撤廃済み、incremental は都度新規作成）
comment_id="$(echo "${summary_json}" | jq -r '.id')"
body="$(echo "${summary_json}" | jq -r '.body')"
# <!-- vibehawk:sha=abc123 --> マーカーから SHA を抽出する
prev_sha="$(echo "${body}" | grep -oE 'vibehawk:sha=[a-f0-9]+' | sed 's/vibehawk:sha=//' | head -1 || echo "")"

if [[ -z "${prev_sha}" ]]; then
  echo "vibehawk: 既存サマリにマーカーがあるが SHA 抽出に失敗 → 完全再レビュー"
  echo "incremental=false" >> "$GITHUB_OUTPUT"
  echo "comment_id=${comment_id}" >> "$GITHUB_OUTPUT"
  echo "prev_sha=" >> "$GITHUB_OUTPUT"
  echo "review_range=" >> "$GITHUB_OUTPUT"
  exit 0
fi

# 前回 SHA が現ブランチの祖先に含まれていれば通常 push、含まれなければ force push / rebase と判断して完全再レビュー
# 仕様: docs/specification.md インクリメンタルレビュー実装パターン
if git cat-file -e "${prev_sha}^{commit}" 2>/dev/null && \
   git merge-base --is-ancestor "${prev_sha}" HEAD 2>/dev/null; then
  review_range="${prev_sha}..HEAD"
  echo "vibehawk: 通常 push 検出 → 範囲: ${review_range}"
  echo "incremental=true" >> "$GITHUB_OUTPUT"
else
  base_sha="$(git merge-base "origin/${BASE_REF}" HEAD 2>/dev/null || echo "")"
  if [[ -n "${base_sha}" ]]; then
    review_range="${base_sha}..HEAD"
    echo "vibehawk: force push / rebase 検出 → 完全再レビュー範囲: ${review_range}"
  else
    review_range=""
    echo "vibehawk: base SHA 取得失敗 → range なし"
  fi
  echo "incremental=false" >> "$GITHUB_OUTPUT"
fi

echo "comment_id=${comment_id}" >> "$GITHUB_OUTPUT"
echo "prev_sha=${prev_sha}" >> "$GITHUB_OUTPUT"
echo "review_range=${review_range}" >> "$GITHUB_OUTPUT"
