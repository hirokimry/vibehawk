#!/usr/bin/env bash
# 用途: `@vibehawk review` コマンドで前回レビュー以降のコミット差分の有無を判定する
#       （Issue #290、epic #289 子1）。差分なしなら LLM 非実行の verdict 再評価経路へ、
#       差分ありなら従来の増分 LLM レビュー経路へ後続 step を分岐させる。
#
# 前回レビュー sha は、自 Bot（vibehawk-for-<owner>[bot]）の review 本文に埋め込まれた
# <!-- vibehawk:sha=<hex> --> マーカーから取得する（find-prev-summary.sh と同型）。
# verdict 再評価経路が POST する review はこのマーカーを含まないため、prev_sha は常に
# 「直近の本物の LLM レビュー sha」を指し、コミットなし連続実行でも差分なし判定が安定する。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
: "${OWNER:?OWNER must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

# GitHub App login は小文字正規化（vibehawk-for-<owner>）。github.repository_owner は大文字
# 保持があり得る（例: "MyOrg"）ため小文字化してから bot login を組む（re-evaluate-verdict.sh と同じ、PR #193）。
# 正規化しないと大文字 owner のリポジトリで自 Bot review が一致せず、差分なし経路に入れない。
normalized_owner="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
BOT_LOGIN="vibehawk-for-${normalized_owner}[bot]"

emit() {
  # $1: diff_exists（true/false）  $2: prev_sha
  echo "diff_exists=$1" >> "$GITHUB_OUTPUT"
  echo "prev_sha=$2" >> "$GITHUB_OUTPUT"
}

# gh api 失敗時は安全側（diff_exists=true=LLM 実行）に倒す。差分判定不能で LLM 非実行に
# 倒すと未レビューのまま verdict だけ動く事故になるため、判定できないときは必ずレビューする。
reviews_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --paginate 2>/dev/null || true)"
if [[ -z "$reviews_json" ]]; then
  echo "::warning::vibehawk: reviews 取得に失敗（rate limit / 認証 / 404）→ 差分ありとして LLM レビューを実行します"
  emit "true" ""
  exit 0
fi

# 自 Bot の review のみ抽出し、body に <!-- vibehawk:summary --> を含む最新を採用する。
# 他ユーザーが summary マーカーを含むコメントを書いても prev_sha が汚染されないよう bot login で絞る。
# ページ横断集約は jq -cs で行う（--paginate --jq はページ単位評価のため、cli/cli#1268）。
summary_body="$(printf '%s' "$reviews_json" \
  | jq -r -s --arg bot "$BOT_LOGIN" '
      [ .[][]
        | select(.user.login == $bot)
        | select((.body // "") | contains("<!-- vibehawk:summary -->")) ]
      | sort_by(.submitted_at) | last // {} | .body // ""')"

prev_sha=""
if [[ -n "$summary_body" ]]; then
  prev_sha="$(printf '%s' "$summary_body" | grep -oE 'vibehawk:sha=[a-f0-9]+' | sed 's/vibehawk:sha=//' | head -1 || true)"
fi

# sha 長検証（外部入力対策）: git sha は 7〜40 文字の hex。範囲外・非 hex は不正として空に倒す
# （巨大値・不正値を GITHUB_OUTPUT に書かない。安全側＝初回扱い＝LLM レビュー）。
if [[ -n "$prev_sha" && ! "$prev_sha" =~ ^[a-f0-9]{7,40}$ ]]; then
  echo "vibehawk: 抽出した prev_sha が不正な形式のため初回扱いにします（Issue #290）"
  prev_sha=""
fi

if [[ -z "$prev_sha" ]]; then
  echo "vibehawk: 前回レビュー sha 未検出 → 差分ありとして LLM レビューを実行します（初回、Issue #290）"
  emit "true" ""
  exit 0
fi

if [[ "$prev_sha" == "$HEAD_SHA" ]]; then
  echo "vibehawk: 前回レビュー sha == HEAD（${HEAD_SHA}）→ 差分なし。指摘の再チェックのみ実施します（Issue #290）"
  emit "false" "$prev_sha"
else
  echo "vibehawk: 前回 ${prev_sha} → HEAD ${HEAD_SHA} に差分あり → 増分 LLM レビューを実行します（Issue #290）"
  emit "true" "$prev_sha"
fi
