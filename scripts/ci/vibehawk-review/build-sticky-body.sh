#!/usr/bin/env bash
# 用途: vibehawk PR sticky walkthrough コメントの body markdown 文字列を生成する（Issue #219）
#
# 入力（環境変数）:
#   STRUCTURED_OUTPUT  claude_review の structured_output（JSON 文字列、空可）
#   DECIDED_EVENT      decide-event.sh の出力（APPROVE / REQUEST_CHANGES / COMMENT、デフォルト COMMENT）
#   HEAD_SHA           PR の HEAD commit SHA（必須）
#   PR_NUMBER          PR 番号（必須）
#   REPO               owner/repo（必須）
#   REVIEW_STATUS      normal / skipped / paused / draft（デフォルト normal）
#   TOOL_FAILURES      外部ツール失敗テキスト（空可、空でなければ WARNING callout に展開）
#
# 出力: 標準出力に sticky 本文 markdown 全体。
#
# 責務:
#   - 入力 jq 解析 + テンプレ整形のみ。
#   - schema validation は upstream（claude-code-action --json-schema + post-bundled-review.sh の jq -e）に委ねる。
#   - POST / PATCH / DELETE は post-sticky-comment.sh の責務（本スクリプトでは行わない）。
#   - STRUCTURED_OUTPUT="" は正常入力として扱う（skip-mark 経路を内部分岐で吸収、別スクリプトを作らない）。

set -euo pipefail

: "${HEAD_SHA:?HEAD_SHA must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${REPO:?REPO must be set}"
STRUCTURED_OUTPUT="${STRUCTURED_OUTPUT:-}"
DECIDED_EVENT="${DECIDED_EVENT:-COMMENT}"
REVIEW_STATUS="${REVIEW_STATUS:-normal}"
TOOL_FAILURES="${TOOL_FAILURES:-}"

printf '%s\n' "<!-- This is an auto-generated comment: sticky-summary by vibehawk -->"
printf '%s\n' "<!-- vibehawk:sticky -->"
printf '%s\n' "<!-- vibehawk:sha=${HEAD_SHA} -->"
printf '\n'
printf '## 🦅 vibehawk レビューサマリ\n\n'

# severity 集計（STRUCTURED_OUTPUT 空時も 0/0/0/0/0 を維持）
if [ -n "$STRUCTURED_OUTPUT" ]; then
  severity_counts=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -c '
    .comments // []
    | reduce .[] as $c (
        {critical:0,major:0,minor:0,trivial:0,info:0};
        if   (($c.body // "") | startswith("🔴")) then .critical += 1
        elif (($c.body // "") | startswith("🟠")) then .major += 1
        elif (($c.body // "") | startswith("🟡")) then .minor += 1
        elif (($c.body // "") | startswith("🔵")) then .trivial += 1
        elif (($c.body // "") | startswith("⚪")) then .info += 1
        else . end
      )')
else
  severity_counts='{"critical":0,"major":0,"minor":0,"trivial":0,"info":0}'
fi

# 高レベル概要（.body 冒頭 1 段落、200 文字超は省略記号で切る）
if [ -n "$STRUCTURED_OUTPUT" ]; then
  body_full=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -r '.body // ""')
  high_summary=$(printf '%s' "$body_full" | awk -v max=200 '
    BEGIN { in_first = 1; total = "" }
    in_first && NF == 0 { in_first = 0; next }
    in_first { total = total (total == "" ? "" : "\n") $0 }
    END {
      if (length(total) > max) printf "%s…", substr(total, 1, max)
      else printf "%s", total
    }')
  if [ -n "$high_summary" ]; then
    printf '### 📝 概要\n\n%s\n\n' "$high_summary"
  fi
fi

# severity 表
printf '### 📊 severity 集計\n\n'
printf '| 🔴 Critical | 🟠 Major | 🟡 Minor | 🔵 Trivial | ⚪ Info |\n'
printf '|---|---|---|---|---|\n'
printf '%s' "$severity_counts" | jq -r '"| " + (.critical|tostring) + " | " + (.major|tostring) + " | " + (.minor|tostring) + " | " + (.trivial|tostring) + " | " + (.info|tostring) + " |"'
printf '\n'

# 主要指摘（🔴 / 🟠 を最大 10 件）
if [ -n "$STRUCTURED_OUTPUT" ]; then
  findings_count=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -r '
    [.comments[]? | select((.body // "") | (startswith("🔴") or startswith("🟠")))] | length')
  if [ "${findings_count:-0}" -gt 0 ]; then
    printf '### 🚨 主要指摘（上位 %s 件）\n\n' "${findings_count}"
    printf '%s' "$STRUCTURED_OUTPUT" | jq -r '
      [.comments[]? | select((.body // "") | (startswith("🔴") or startswith("🟠")))]
      | .[:10]
      | .[]
      | "- `" + (.path) + ":" + ((.line // 0) | tostring) + "` — " + ((.body // "") | gsub("\n"; " ") | .[0:80])'
    printf '\n'
  fi
fi

# Review Status callout（normal 以外で表示）
case "$REVIEW_STATUS" in
  normal) ;;
  skipped)
    printf '> [!NOTE]\n> ⏭️ レビュー対象なし（paths-ignore 全マッチ）。skip-mark workflow が `vibehawk` を success で post 済み。\n\n'
    ;;
  paused)
    printf '> [!NOTE]\n> ⏸️ レビュー一時停止中。\n\n'
    ;;
  draft)
    printf '> [!NOTE]\n> 📝 draft PR のためレビュー保留中。ready_for_review でレビューが走ります。\n\n'
    ;;
  *)
    printf '> [!NOTE]\n> ℹ️ REVIEW_STATUS=%s\n\n' "$REVIEW_STATUS"
    ;;
esac

# Tool failures callout
if [ -n "$TOOL_FAILURES" ]; then
  printf '> [!WARNING]\n> 🔧 外部ツール起動失敗\n'
  printf '%s' "$TOOL_FAILURES" | awk '{ printf "> %s\n", $0 }'
  printf '\n'
fi

# Walkthrough（.body の残り全体、折り畳み）
if [ -n "$STRUCTURED_OUTPUT" ] && [ -n "${body_full:-}" ]; then
  walkthrough_body=$(printf '%s' "$body_full" | awk '
    BEGIN { in_first = 1; out = "" }
    in_first && NF == 0 { in_first = 0; next }
    in_first { next }
    { out = out (out == "" ? "" : "\n") $0 }
    END { printf "%s", out }')
  if [ -n "$walkthrough_body" ]; then
    printf '<details>\n<summary>📖 詳細レビュー</summary>\n\n%s\n\n</details>\n\n' "$walkthrough_body"
  fi
fi

# Internal state JSON（マーカーで囲み、次回 incremental 判定の根拠）
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
state_json=$(jq -nc \
  --arg sha "$HEAD_SHA" \
  --arg event "$DECIDED_EVENT" \
  --argjson sev "$severity_counts" \
  --arg status "$REVIEW_STATUS" \
  --arg ts "$timestamp" \
  '{last_sha: $sha, decided_event: $event, severity: $sev, review_status: $status, timestamp: $ts}')

printf '<!-- vibehawk:state %s -->\n' "$state_json"
