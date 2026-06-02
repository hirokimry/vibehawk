#!/usr/bin/env bash
# 用途: 自動レビューが paused / ignored の PR で `vibehawk` status check を success「一時停止中」で
#       post する（Issue #295、epic #289 子6）。auto-review を skip しても required status check を
#       緑に保ち、merge をブロックしない。手動 `@vibehawk review` で通常レビューに復帰できる。
#
# post-status-check.sh（review 結果から conclusion を導出する単一責務）とは責務を分離し、
# paused/ignored 専用の success post を本スクリプトが担う。

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN must be set}"
: "${REPO:?REPO must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"
: "${AUTOREVIEW_STATE:?AUTOREVIEW_STATE must be set}"

case "$AUTOREVIEW_STATE" in
  paused)  label="一時停止中（paused）" ;;
  ignored) label="対象外（ignored）" ;;
  *)
    echo "vibehawk: AUTOREVIEW_STATE=${AUTOREVIEW_STATE} は paused/ignored ではないため skip（Issue #295）"
    exit 0
    ;;
esac

summary="🦅 vibehawk: 自動レビューは ${label} です。手動の \`@vibehawk review\` で通常レビューを実行できます。\`@vibehawk resume\` で自動レビューを再開します。"

gh api -X POST "repos/${REPO}/check-runs" \
  --field name="vibehawk" \
  --field head_sha="${HEAD_SHA}" \
  --field status="completed" \
  --field conclusion="success" \
  --field "output[title]=vibehawk: 自動レビュー ${label}" \
  --field "output[summary]=${summary}"

echo "vibehawk: autoreview ${AUTOREVIEW_STATE} → vibehawk status check を success で post しました（Issue #295）"
