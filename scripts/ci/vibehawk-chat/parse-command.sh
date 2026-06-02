#!/usr/bin/env bash
# 用途: `@vibehawk` メンションコメントから単一のコマンド値を厳密 parse する（Issue #289、CodeRabbit 指摘対応）。
#       後続の全 step はこの `command` 出力だけで分岐し、`contains()` の部分一致による誤発火を排除する。
#
# 判定規則（厳密化）: コメントの **いずれかの行が trim 後に厳密に `@vibehawk <cmd>` と一致** する場合のみ
# その command と判定する。会話文中の引用・説明（例: `@vibehawk review と full review の違いは?`、
# `@vibehawk pause の説明を書きたい`）は行全体が一致しないため command にならず chat 扱いになる。
# vibehawk の各コマンドは引数を取らないため、行全体一致で過不足ない。
#
# 出力: command = review / full-review / resolve / summary / help / configuration / pause / resume / ignore / chat

set -euo pipefail

: "${COMMENT_BODY:?COMMENT_BODY must be set}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

command="chat"
while IFS= read -r line; do
  # 行頭・行末の空白を除去（CR も含む。Windows 改行混入対策）
  trimmed="$(printf '%s' "$line" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$trimmed" in
    "@vibehawk full review")   command="full-review"; break ;;
    "@vibehawk review")        command="review"; break ;;
    "@vibehawk resolve")       command="resolve"; break ;;
    "@vibehawk summary")       command="summary"; break ;;
    "@vibehawk help")          command="help"; break ;;
    "@vibehawk configuration") command="configuration"; break ;;
    "@vibehawk pause")         command="pause"; break ;;
    "@vibehawk resume")        command="resume"; break ;;
    "@vibehawk ignore")        command="ignore"; break ;;
  esac
done <<EOF
${COMMENT_BODY}
EOF

echo "vibehawk: 検出コマンド = ${command}（Issue #289、厳密行一致 parse）"
echo "command=${command}" >> "$GITHUB_OUTPUT"
