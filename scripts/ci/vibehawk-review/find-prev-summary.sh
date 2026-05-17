#!/usr/bin/env bash
# scripts/ci/vibehawk-review/find-prev-summary.sh
#
# vibehawk-review.yml の "前回サマリコメントを取得（Issue #8 インクリメンタル
# レビュー判定）" ステップ（旧 L109 インライン）の本体。
#
# bundled review POST 移行後（Issue #121）、サマリは `POST /repos/X/Y/pulls/N/reviews`
# の review body に埋め込まれる。本スクリプトは vibehawk bot の review を全件取得し、
# `<!-- vibehawk:summary -->` と `<!-- vibehawk:sha=<hex> -->` マーカーを使って前回
# サマリと前回 SHA を抽出し、incremental レビュー範囲を決定する。
#
# 入力 env:
#   GH_TOKEN    — App installation token（vibehawk-for-<owner>[bot] 名義）
#   PR_NUMBER   — 対象 PR の番号
#   REPO        — owner/repo
#   OWNER       — リポジトリオーナー名
#   BASE_REF    — PR の base ブランチ名
#
# 出力 GITHUB_OUTPUT:
#   incremental=true|false
#   comment_id=<review id or empty>
#   prev_sha=<hex or empty>
#   review_range=<prev_sha..HEAD or base_sha..HEAD or empty>

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${OWNER:?OWNER must be set}"
: "${BASE_REF:?BASE_REF must be set}"

BOT_LOGIN="vibehawk-for-${OWNER}[bot]"

# Issue #121: bundled review API へ移行
# サマリは `POST /repos/X/Y/pulls/N/reviews` の review body に埋め込まれるため、
# 前回サマリの検索元は pulls/reviews エンドポイントとなる。
# 投稿者 ID + 種別マーカーの二重チェックで vibehawk の review を特定。
# 旧 issue comment 形式のサマリ（Issue #121 以前）は無視されるが、誤判定はしない
# （種別マーカー <!-- vibehawk:summary --> は review body にも引き続き含まれる）。
# null は jq で空文字に変換（`.body // ""`）、複数ヒット時は submitted_at 最新を採用。
# `gh api --paginate --jq` はページ単位で jq が評価され、複数ページに分散したレビューでは
# 全件中の最新 1 件を正しく取得できないため、`--paginate` の生 JSON を `jq -cs`（slurp）で
# ページ横断集約してから一括フィルタする（cli/cli#1268 / #10459 参照）。
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

# comment_id は GitHub Reviews API では review.id（PATCH 不可、bundled review 化により edit 経路は撤廃）。
# 後方互換のため GITHUB_OUTPUT には残すが prompt 側では使わない（incremental は新規 review を都度作成）。
comment_id="$(echo "${summary_json}" | jq -r '.id')"
body="$(echo "${summary_json}" | jq -r '.body')"
# SHA マーカー <!-- vibehawk:sha=<hex> --> から SHA を抽出
# （<!-- vibehawk:sha=abc123 --> から abc123 を取り出す）
prev_sha="$(echo "${body}" | grep -oE 'vibehawk:sha=[a-f0-9]+' | sed 's/vibehawk:sha=//' | head -1 || echo "")"

if [[ -z "${prev_sha}" ]]; then
  echo "vibehawk: 既存サマリにマーカーがあるが SHA 抽出に失敗 → 完全再レビュー"
  echo "incremental=false" >> "$GITHUB_OUTPUT"
  echo "comment_id=${comment_id}" >> "$GITHUB_OUTPUT"
  echo "prev_sha=" >> "$GITHUB_OUTPUT"
  echo "review_range=" >> "$GITHUB_OUTPUT"
  exit 0
fi

# force push / rebase 検出（仕様: docs/specification.md インクリメンタルレビュー実装パターン）
# 前回 SHA が現ブランチに含まれていれば通常 push、含まれていなければ完全再レビュー
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
