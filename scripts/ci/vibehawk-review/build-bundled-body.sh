#!/usr/bin/env bash
# 用途: vibehawk bundled review の本文 markdown を構造化フィールドから決定論的に組み立てる（Issue #271）
#
# CodeRabbit 互換のレビュー本文（インラインをまとめるコメント、マーカー <!-- vibehawk:summary -->）を
# comments[] から組み立てる。本スクリプトは以下を出力する（標準出力）:
#   1. `**Actionable comments posted: N**`（actionable = category が 🧹 Nitpick 以外の件数）
#   2. 🧹 Nitpick comments (M) 折り畳み（category が 🧹 Nitpick の指摘をファイル別ネストで集約）
#   3. 末尾マーカー <!-- vibehawk:summary --> / <!-- vibehawk:sha=<commit_id> -->
#      （find-prev-summary.sh が前回 SHA を抽出するインクリメンタルレビューの一意特定に必須、Issue #57）
#
# Claude が返す severity 別件数サマリ（.body）は本スクリプトが置き換える。物語/Changes/severity 表は
# sticky walkthrough（build-sticky-body.sh）に一本化されるため本文には出さない（Issue #269）。
#
# nitpick のインライン除外（routing）は呼び出し元 post-bundled-review.sh が行う。
# 本スクリプトは読み取り専用（payload を書き換えない）。combined AI プロンプト（Issue #272）と
# Review info（Issue #273）は後続 Issue で本スクリプトに追加される。
#
# 入力: payload JSON ファイルパス（引数 $1）。.comments[] と .commit_id を読む。
# 出力: 標準出力に本文 markdown 全体。

set -euo pipefail

PAYLOAD="${1:?payload JSON ファイルパスを引数で渡してください}"

if [[ ! -f "$PAYLOAD" ]]; then
  echo "::error::build-bundled-body: payload ファイルが存在しません: ${PAYLOAD}" >&2
  exit 1
fi

# Issue #273: ℹ️ Review info（その回が見た差分の snapshot、回ごとの監査記録）。
# sticky walkthrough の Recent review info（最新回・可変）とは別物で、レビュー本文側は
# POST 時に凍結されるため過去回が履歴として残る。env が全て空なら非出力（後方互換）。
RUN_ID="${RUN_ID:-}"
COMMITS_JSON="${COMMITS_JSON:-}"
FILES_SELECTED_JSON="${FILES_SELECTED_JSON:-}"

review_info=""
if [ -n "$RUN_ID" ] || [ -n "$COMMITS_JSON" ] || [ -n "$FILES_SELECTED_JSON" ]; then
  review_info+=$'<details>\n<summary>ℹ️ Review info</summary>\n\n'

  if [ -n "$RUN_ID" ]; then
    review_info+=$'<details>\n<summary>⚙️ Run configuration</summary>\n\n'
    review_info+=$'| 項目 | 値 |\n|---|---|\n'
    review_info+=$'| Config path | `.vibehawk.yaml` |\n'
    review_info+=$'| Review profile | vibehawk fixed |\n'
    review_info+=$'| Plan | OSS |\n'
    review_info+="| Run ID | ${RUN_ID} |"$'\n'
    review_info+=$'\n</details>\n\n'
  fi

  if [ -n "$COMMITS_JSON" ]; then
    commits_count=$(printf '%s' "$COMMITS_JSON" | jq -r 'length // 0')
    if [ "${commits_count:-0}" -gt 0 ]; then
      first_short=$(printf '%s' "$COMMITS_JSON" | jq -r '.[0].sha // ""' | cut -c1-7)
      last_short=$(printf '%s' "$COMMITS_JSON" | jq -r '.[-1].sha // ""' | cut -c1-7)
      review_info+=$'<details>\n<summary>📥 Commits</summary>\n\n'
      review_info+="Reviewing files that changed from the base of the PR and between ${first_short} and ${last_short}."$'\n'
      review_info+=$'\n</details>\n\n'
    fi
  fi

  if [ -n "$FILES_SELECTED_JSON" ]; then
    selected_count=$(printf '%s' "$FILES_SELECTED_JSON" | jq -r 'length // 0')
    review_info+="<details>"$'\n'"<summary>📒 Files selected for processing (${selected_count:-0})</summary>"$'\n\n'
    if [ "${selected_count:-0}" -gt 0 ]; then
      files_list=$(printf '%s' "$FILES_SELECTED_JSON" | jq -r '.[] | "- `" + . + "`"')
      review_info+="${files_list}"$'\n'
    fi
    review_info+=$'\n</details>\n\n'
  fi

  review_info+=$'</details>\n\n'
fi

# jq で本文を組み立てる。string interpolation \(...) は使わず + で連結する（shell.md）。
# nitpick はファイル別に group_by し、各指摘を「行参照 + effort ラベル + 太字タイトル + 説明
# + 🔧 提案差分(任意) + 🤖 AI 向け修正指示」で描画する（severity は付けない、Issue #270）。
# shellcheck disable=SC2016  # 単一引用符は意図的。`.body` 等は jq 式でありシェル展開させない。
JQ_PROGRAM='
def render_nit:
  (
    if (.start_line != null) then ((.start_line|tostring) + "-" + ((.line // .start_line)|tostring))
    elif (.line != null) then (.line|tostring)
    else "" end
  ) as $lref
  | (if ($lref | length) > 0 then "`" + $lref + "`: " else "" end)
    + "_" + .effort + "_\n\n"
    + "**" + .title + "**\n\n"
    + .description
    + (if ((.suggestion // "") | length) > 0 then
        "\n\n<details>\n<summary>🔧 提案差分</summary>\n\n```suggestion\n" + .suggestion + "\n```\n\n</details>"
      else "" end)
    + "\n\n<details>\n<summary>🤖 AI 向け修正指示</summary>\n\n```\n" + .ai_prompt + "\n```\n\n</details>";

# Issue #272: 全指摘の ai_prompt をファイル別（@path 見出し）に束ねる。
# 人が AI エージェントへ一括貼り付けして全指摘を直せるようにする（CodeRabbit の
# "Prompt for all review comments with AI agents" 相当、文言は vibehawk 独自）。
def render_prompt_group:
  group_by(.path)
  | map("@" + (.[0].path) + ":\n" + (map("- " + .ai_prompt) | join("\n")))
  | join("\n\n");

(.comments // []) as $all
| (.commit_id // "") as $sha
| [$all[] | select(.category != "🧹 Nitpick")] as $actionable
| [$all[] | select(.category == "🧹 Nitpick")] as $nits
| "**Actionable comments posted: " + (($actionable | length) | tostring) + "**\n\n"
  + (if ($nits | length) > 0 then
      "<details>\n<summary>🧹 Nitpick comments (" + (($nits | length) | tostring) + ")</summary><blockquote>\n\n"
      + ( $nits
          | group_by(.path)
          | map(
              (.[0].path) as $path
              | "<details>\n<summary>" + $path + " (" + ((length)|tostring) + ")</summary><blockquote>\n\n"
                + ( map(render_nit) | join("\n\n---\n\n") )
                + "\n\n</blockquote></details>"
            )
          | join("\n\n")
        )
      + "\n\n</blockquote></details>\n\n"
    else "" end)
  + (if ($all | length) > 0 then
      "<details>\n<summary>🤖 全指摘の AI 向け修正指示（一括）</summary>\n\n```\n"
      + "各指摘を現在のコードと突き合わせて検証し、まだ有効なものだけを最小限の変更で修正してください。無効な指摘は理由を添えてスキップしてください。\n\n"
      + (if ($actionable | length) > 0 then "actionable:\n" + ($actionable | render_prompt_group) + "\n\n" else "" end)
      + (if ($nits | length) > 0 then "nitpick:\n" + ($nits | render_prompt_group) + "\n" else "" end)
      + "```\n\n</details>\n\n"
    else "" end)
  + $review_info
  + "<!-- vibehawk:summary -->\n"
  + "<!-- vibehawk:sha=" + $sha + " -->"
'

jq -r --arg review_info "$review_info" "$JQ_PROGRAM" "$PAYLOAD"
