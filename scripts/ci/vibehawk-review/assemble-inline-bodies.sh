#!/usr/bin/env bash
# 用途: vibehawk インライン指摘の構造化フィールドから最終 body を組み立てる（Issue #263）
#
# Claude は comments[] に構造化フィールド（category / severity / effort / title /
# description / suggestion? / ai_prompt）を出力する。本スクリプトはそれを CodeRabbit 互換の
# body 文字列に決定論的に組み立て、GitHub Reviews API が受け付けるフィールド
# （path / line / side / start_line / start_side / body）のみへ絞り込む。
# 固定テンプレート（📝 Committable suggestion / > [!IMPORTANT] 注意書き /
# 🤖 AI 向け修正指示 / <!-- vibehawk:inline --> フッタ）は本スクリプトが付与する責務を持つ。
#
# 入力: payload JSON ファイルパス（引数 $1）を in-place で書き換える。
# 呼び出し元 post-bundled-review.sh は書き換え後の同一ファイルを継続参照する。

set -euo pipefail

PAYLOAD="${1:?payload JSON ファイルパスを引数で渡してください}"

if [[ ! -f "$PAYLOAD" ]]; then
  echo "::error::assemble-inline-bodies: payload ファイルが存在しません: ${PAYLOAD}"
  exit 1
fi

# jq で comments[] を組み立てる。string interpolation \(...) は使わず + 連結する（shell.md）。
# suggestion が非空のときのみ Committable suggestion 折り畳みを挿入する。
# line / side / start_line / start_side は存在する場合のみ保持し、欠落キーを捏造しない。
#
# .comments が配列でない / 欠落する不正入力では変換せず素通しする。本スクリプトは
# post-bundled-review.sh の jq 契約検証より前段で走るため、ここでクラッシュすると検証の
# graceful skip（exit 0 + ::warning::）経路を奪う。配列のときだけ組み立てる（二重防御）。
# shellcheck disable=SC2016  # 単一引用符は意図的。`$body` 等は jq 変数でありシェル展開させない。
JQ_PROGRAM='
if (.comments | type) != "array" then . else
.comments |= map(
  (
    "_" + .category + "_ | _" + .severity + "_ | _" + .effort + "_\n\n"
    + "**" + .title + "**\n\n"
    + .description
    + (if ((.suggestion // "") | length) > 0 then
        "\n\n<!-- suggestion_start -->\n\n"
        + "<details>\n<summary>📝 Committable suggestion</summary>\n\n"
        + "> [!IMPORTANT]\n> コミット前に内容を確認してください。ハイライト箇所を正確に置き換え、欠落やインデント崩れが無いことを確かめてからコミットできます。\n\n"
        + "```suggestion\n" + .suggestion + "\n```\n\n"
        + "</details>\n\n"
        + "<!-- suggestion_end -->"
      else "" end)
    + "\n\n<details>\n<summary>🤖 AI 向け修正指示</summary>\n\n"
    + "```\n" + .ai_prompt + "\n```\n\n"
    + "</details>\n\n"
    + "<!-- vibehawk:inline -->"
  ) as $body
  | {path: .path, body: $body}
    + (if has("line") then {line: .line} else {} end)
    + (if has("side") then {side: .side} else {} end)
    + (if has("start_line") then {start_line: .start_line} else {} end)
    + (if has("start_side") then {start_side: .start_side} else {} end)
)
end
'

# 同一ディレクトリに一時ファイルを作って mv（BSD/GNU 互換、sed -i 禁止、shell.md）
tmp="$(mktemp "$(dirname "$PAYLOAD")/.$(basename "$PAYLOAD").XXXXXX")"
jq "$JQ_PROGRAM" "$PAYLOAD" > "$tmp" && mv "$tmp" "$PAYLOAD"

echo "vibehawk: インライン指摘の body を構造化フィールドから組み立てました（Issue #263）"
