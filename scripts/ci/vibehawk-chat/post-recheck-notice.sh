#!/usr/bin/env bash
# 用途: `@vibehawk review` の差分なし経路で「指摘の再チェックのみ実施した」ことを
#       利用者に通知する chat コメントを投稿する（Issue #290、epic #289 子1）。
#
# re-evaluate-verdict.sh が出力した DECIDED_EVENT（SKIP / APPROVE / REQUEST_CHANGES）に応じて
# 文面を分岐する。verdict 自体の更新は re-evaluate-verdict.sh が review POST で行い、本スクリプトは
# 「なぜ差分なしでも判定が動いた / 動かなかったか」を利用者に伝える通知に徹する。
#
# 無限ループ防止: 本文に @vibehawk を含めない（含めると次回 issue_comment トリガーで再発火する）。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER must be set}"
: "${DECIDED_EVENT:?DECIDED_EVENT must be set}"

# UNRESOLVED_COUNT は REQUEST_CHANGES 時のみ使う。未設定でも安全に動くよう既定値を置く。
# 整数以外（想定外の step output）は本文へ混入させず 0 に倒す（防御的）。
UNRESOLVED_COUNT="${UNRESOLVED_COUNT:-0}"
if [[ ! "$UNRESOLVED_COUNT" =~ ^[0-9]+$ ]]; then
  UNRESOLVED_COUNT="0"
fi

case "$DECIDED_EVENT" in
  SKIP)
    body="🦅 vibehawk: 差分なし → 指摘の再チェックのみ実施しました。この PR には vibehawk の指摘が無いため、レビュー判定は変更していません。"
    ;;
  APPROVE)
    body="🦅 vibehawk: 差分なし → 指摘の再チェックのみ実施しました。指摘が全て解決済みのため、レビュー判定を ✅ APPROVE に更新しました。"
    ;;
  REQUEST_CHANGES)
    body="🦅 vibehawk: 差分なし → 指摘の再チェックのみ実施しました。未解決の指摘が ${UNRESOLVED_COUNT} 件あるため、変更要求（CHANGES_REQUESTED）を維持します。"
    ;;
  *)
    # 想定外の値でも安全に汎用文面でフォールバックする（堅牢性）
    body="🦅 vibehawk: 差分なし → 指摘の再チェックのみ実施しました。"
    ;;
esac

gh issue comment "$ISSUE_NUMBER" --body "$body"
