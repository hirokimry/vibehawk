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

# Issue #282: nitpick 件数を routing より前に数える（後段の APPROVE 時 body 空化の分岐で使う）。
# routing（line 37 付近）で .comments から nitpick が除かれるため、ここで先に取得する。
nitpick_count="$(jq '[.comments[]? | select(.category == "🧹 Nitpick")] | length' "$PAYLOAD")"

# Issue #271: レビュー本文（インラインをまとめるコメント）を build-bundled-body.sh で
# 構造化フィールドから決定論的に組み立てる（CodeRabbit 互換: Actionable 件数 + 🧹 Nitpick comments）。
# nitpick を含む raw comments を読むため、nitpick の routing より前に実行する。
# 失敗時は graceful skip（exit 0 + ::warning::、次の status check が neutral に倒れる）。
if ! BUNDLED_BODY="$(bash "$(dirname "$0")/build-bundled-body.sh" "$PAYLOAD")"; then
  echo "::warning::vibehawk: build-bundled-body に失敗したため bundled review POST を skip します（次の status check post が neutral に倒れます）"
  exit 0
fi

# Issue #271: nitpick（category=🧹 Nitpick）はインラインスレッドに出さず本文に集約する。
# inline 投稿対象から除外し（routing）、actionable のみ comments[] に残す。
ROUTED="${RUNNER_TEMP}/vibehawk-review.routed.json"
jq '.comments |= ([.[]? | select(.category != "🧹 Nitpick")])' "$PAYLOAD" > "$ROUTED" && mv "$ROUTED" "$PAYLOAD"

# Issue #263: actionable の comments[] を最終 body へ組み立て、GitHub Reviews API 有効フィールド
# （path/line/side/start_line/start_side/body）のみへ絞り込む。以降の jq 契約検証は組み立て後の body を検査する。
if ! bash "$(dirname "$0")/assemble-inline-bodies.sh" "$PAYLOAD"; then
  echo "::warning::vibehawk: assemble-inline-bodies に失敗したため bundled review POST を skip します（次の status check post が neutral に倒れます）"
  exit 0
fi

# Issue #271: レビュー本文を build-bundled-body.sh の出力で上書きする（Claude の .body は使わない、
# 物語/Changes/severity 表は sticky walkthrough に一本化されるため、Issue #269）。
SET_BODY="${RUNNER_TEMP}/vibehawk-review.body.json"
jq --arg b "$BUNDLED_BODY" '.body = $b' "$PAYLOAD" > "$SET_BODY" && mv "$SET_BODY" "$PAYLOAD"

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

# Issue #222 / #282: APPROVE 時の body 空化は 🧹 Nitpick が無いときのみ行う。
# 元の趣旨（#222）は「APPROVE 時に冗長な severity サマリを毎回出さない（サマリは sticky に再掲あり）」
# だったが、#274 でサマリは撤去され、現在 body に載るのは sticky に無い 🧹 Nitpick comments。
# よって nitpick がある APPROVE で body を空化すると nitpick が消える（#280 で実発生）。
# CodeRabbit は APPROVE（空 body）+ 別 COMMENTED で nitpick を出すが、vibehawk は 1 本集約のため
# APPROVE 時も nitpick があれば body を保持して nitpick を残す（Issue #282）。
# nitpick が無い（truly-clean）APPROVE は従来どおり body と comments を空化する。
if [[ "$DECIDED_EVENT" == "APPROVE" ]]; then
  if [[ "${nitpick_count:-0}" -gt 0 ]]; then
    echo "vibehawk: DECIDED_EVENT=APPROVE だが 🧹 Nitpick ${nitpick_count} 件あるため body を保持して POST します（nitpick を消さない、Issue #282）"
  else
    jq '.body = "" | .comments = []' "$PAYLOAD" > "$OVERRIDDEN" && mv "$OVERRIDDEN" "$PAYLOAD"
    echo "vibehawk: DECIDED_EVENT=APPROVE かつ 🧹 Nitpick 0 件のため body と comments を空に上書きしました（CodeRabbit 模倣、Issue #222/#282）"
  fi
fi

event="$(jq -r '.event' "$PAYLOAD")"
comments_count="$(jq -r '.comments | length' "$PAYLOAD")"
echo "vibehawk: bundled review を post します（event=${event}, comments=${comments_count} 件、event は decide_event step の決定論的計算結果で上書き済み、Issue #166）"

gh api -X POST "repos/${REPO}/pulls/${PR_NUMBER}/reviews" --input "$PAYLOAD"

echo "vibehawk: bundled review を post しました"
