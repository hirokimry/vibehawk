#!/usr/bin/env bash
# scripts/ci/vibehawk-review/post-bundled-review.sh
#
# vibehawk-review.yml の "vibehawk bundled review を post（Issue #164 fix / Issue #166）"
# ステップ（旧 L560 インライン）の本体。
#
# claude-code-action の `outputs.structured_output`（--json-schema で schema validated
# 済み）を受け取り、GitHub Reviews API 契約の二重防御 validation を行い、`event`
# フィールドを `decide-event.sh` の決定値で上書きしてから `gh api -X POST` で 1 回だけ
# bundled review を POST する。
#
# 入力 env:
#   GH_TOKEN            — App installation token（vibehawk-for-<owner>[bot] 名義）
#   REPO                — owner/repo
#   PR_NUMBER           — 対象 PR の番号
#   STRUCTURED_OUTPUT   — claude-code-action outputs.structured_output（JSON 文字列）
#   DECIDED_EVENT       — decide-event.sh の出力 (APPROVE / REQUEST_CHANGES / COMMENT)
#   RUNNER_TEMP         — GitHub Actions runner の一時ディレクトリ
#
# 終了コード:
#   0 — POST 成功 / validation 失敗（次の status check post を neutral に倒すために skip）
#   非 0 — gh api POST 失敗（GitHub API エラー）

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${STRUCTURED_OUTPUT:?STRUCTURED_OUTPUT must be set}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"

PAYLOAD="${RUNNER_TEMP}/vibehawk-review.json"

# claude-code-action の outputs.structured_output（--json-schema で schema validated 済み）を
# workflow step 側で決定論的にファイル化する。`printf '%s'` を使うことで `echo` の `-n` 解釈や
# 末尾改行追加の差異を回避し、JSON 内のエスケープ済 `\"` / `\n` / マルチバイト文字を破壊しない。
printf '%s' "$STRUCTURED_OUTPUT" > "$PAYLOAD"

# JSON 構造検証（schema validation の二重防御、PR #153 CodeRabbit Major 指摘対応で強化）:
# トップレベルキーの存在だけでは不十分（event="INVALID" や壊れた comments[] の shape を
# 通過させてしまい、後段の gh api POST が 422 で fail し status check post step に到達できなくなる）。
# GitHub Reviews API の契約に従って事前 validation する:
#   - .event は "APPROVE" / "REQUEST_CHANGES" / "COMMENT" のいずれか
#   - .body / .commit_id は非空文字列
#   - .comments は配列で、各要素は path/body 必須、line/side/start_line/start_side は型整合
if ! jq -e '
  (.event == "APPROVE" or .event == "REQUEST_CHANGES" or .event == "COMMENT")
  and (.body | type == "string" and length > 0)
  and (.commit_id | type == "string" and length > 0)
  and (.comments | type == "array")
  and all(.comments[]?;
    (.path | type == "string" and length > 0)
    and (.body | type == "string" and length > 0)
    and ((has("line") | not) or (.line | type == "number"))
    and ((has("side") | not) or (.side == "LEFT" or .side == "RIGHT"))
    and ((has("start_line") | not) or (.start_line | type == "number"))
    and ((has("start_side") | not) or (.start_side == "LEFT" or .start_side == "RIGHT"))
  )
' "$PAYLOAD" > /dev/null; then
  echo "::warning::vibehawk: outputs.structured_output の jq 契約検証に失敗しました（GitHub Reviews API 契約違反: event 値不正 / 必須キー欠落 / comments[] shape 不正など）。bundled review POST を skip します（次の status check post が neutral に倒れます）"
  exit 0
fi

# Issue #166: event フィールドを decide_event step の計算結果で上書きする。
# Claude が返した event は placeholder（schema 上は APPROVE / REQUEST_CHANGES / COMMENT の
# いずれか、prompt 規約では COMMENT 固定）であり、最終的な event 判定は decide_event step が
# unresolved 数 + 新規 Critical/Major 件数から決定論的に行う。jq で .event を上書きしてから
# POST することで、Claude の確率的応答に依存しない event 決定を実現する。
if [[ -z "${DECIDED_EVENT:-}" ]]; then
  echo "::warning::vibehawk: decide_event step の出力 (decided_event) が空です。bundled review POST を skip します（次の status check post が neutral に倒れます）"
  exit 0
fi
if [[ "$DECIDED_EVENT" != "APPROVE" && "$DECIDED_EVENT" != "REQUEST_CHANGES" && "$DECIDED_EVENT" != "COMMENT" ]]; then
  echo "::warning::vibehawk: decide_event step の出力 (decided_event=${DECIDED_EVENT}) が GitHub Reviews API の許容値 (APPROVE/REQUEST_CHANGES/COMMENT) ではありません。bundled review POST を skip します"
  exit 0
fi
OVERRIDDEN="${RUNNER_TEMP}/vibehawk-review.overridden.json"
jq --arg ev "$DECIDED_EVENT" '.event = $ev' "$PAYLOAD" > "$OVERRIDDEN"
mv "$OVERRIDDEN" "$PAYLOAD"

event="$(jq -r '.event' "$PAYLOAD")"
comments_count="$(jq -r '.comments | length' "$PAYLOAD")"
echo "vibehawk: bundled review を post します（event=${event}, comments=${comments_count} 件、event は decide_event step の決定論的計算結果で上書き済み、Issue #166）"

# 決定論的に 1 回だけ POST（試し打ちなし、Issue #152）
gh api -X POST "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --input "$PAYLOAD"

echo "vibehawk: bundled review を post しました"
