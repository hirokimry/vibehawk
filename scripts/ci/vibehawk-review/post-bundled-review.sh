#!/usr/bin/env bash
# 用途: vibehawk-review.yml の bundled review POST ステップ本体（Issue #164 fix / #166 / #222）
#
# structured_output の二重防御 validation を行い、decide-event.sh の決定値で
# event フィールドを上書きしてから 1 回だけ POST する（試し打ちなし、Issue #152）。
# validation 失敗は skip して exit 0（次の status check step が neutral に倒れる）。
#
# Issue #222: DECIDED_EVENT=APPROVE のときは .body と .comments を空に上書きしてから POST する
# （CodeRabbit と同じ挙動。approve なのに長文サマリが毎回出るのは PR タイムラインのノイズになる）。
# サマリは Issue #219 の sticky walkthrough コメント経路（issue-comment）で別途残るため、
# レビュー本文を消しても CEO は引き続きサマリを参照できる。

set -euo pipefail

: "${REPO:?REPO must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${STRUCTURED_OUTPUT:?STRUCTURED_OUTPUT must be set}"
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"

PAYLOAD="${RUNNER_TEMP}/vibehawk-review.json"

# `echo` は -n の解釈や末尾改行の差異があるため `printf '%s'` を使う（JSON のエスケープを破壊しない）
printf '%s' "$STRUCTURED_OUTPUT" > "$PAYLOAD"

# Issue #263: Claude は comments[] に構造化フィールド（category / severity / effort / title /
# description / suggestion? / ai_prompt）を出力する。検証の前段で最終 body へ組み立て、
# GitHub Reviews API 有効フィールド（path/line/side/start_line/start_side/body）のみへ絞り込む。
# 以降の jq 契約検証は組み立て後の body（length > 0）を検査する。
bash "$(dirname "$0")/assemble-inline-bodies.sh" "$PAYLOAD"

# トップレベルキーの存在だけでは gh api POST が 422 で落ちて status check step に到達できなくなる（PR #153）。
# GitHub Reviews API 契約に沿って事前 validation する（二重防御）:
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

# Claude の event は placeholder であり、decide_event step が決定論的に算出した値で上書きしてから POST する（Issue #166）
if [[ -z "${DECIDED_EVENT:-}" ]]; then
  echo "::warning::vibehawk: decide_event step の出力 (decided_event) が空です。bundled review POST を skip します（次の status check post が neutral に倒れます）"
  exit 0
fi
if [[ "$DECIDED_EVENT" != "APPROVE" && "$DECIDED_EVENT" != "REQUEST_CHANGES" && "$DECIDED_EVENT" != "COMMENT" ]]; then
  echo "::warning::vibehawk: decide_event step の出力 (decided_event=${DECIDED_EVENT}) が GitHub Reviews API の許容値 (APPROVE/REQUEST_CHANGES/COMMENT) ではありません。bundled review POST を skip します"
  exit 0
fi
OVERRIDDEN="${RUNNER_TEMP}/vibehawk-review.overridden.json"
jq --arg ev "$DECIDED_EVENT" '.event = $ev' "$PAYLOAD" > "$OVERRIDDEN" && mv "$OVERRIDDEN" "$PAYLOAD"

# Issue #222: APPROVE 時は body と comments を空に上書きする（CodeRabbit 模倣）。
# サマリは sticky walkthrough コメント経路（Issue #219）で別途残る。
# 既存 validation（line 22-38）の `.body | length > 0` は変更しない。validation は Claude の
# 非空 body を従来通り検査し、validation 通過後にここで空に上書きする。
if [[ "$DECIDED_EVENT" == "APPROVE" ]]; then
  jq '.body = "" | .comments = []' "$PAYLOAD" > "$OVERRIDDEN" && mv "$OVERRIDDEN" "$PAYLOAD"
  echo "vibehawk: DECIDED_EVENT=APPROVE のため body と comments を空に上書きしました（CodeRabbit 模倣、サマリは sticky comment 経路で残る、Issue #222）"
fi

event="$(jq -r '.event' "$PAYLOAD")"
comments_count="$(jq -r '.comments | length' "$PAYLOAD")"
echo "vibehawk: bundled review を post します（event=${event}, comments=${comments_count} 件、event は decide_event step の決定論的計算結果で上書き済み、Issue #166）"

gh api -X POST "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --input "$PAYLOAD"

echo "vibehawk: bundled review を post しました"
