#!/usr/bin/env bash
# 用途: vibehawk PR sticky walkthrough コメントの body markdown 文字列を生成する（Issue #219 / #226）
#
# 入力（環境変数）:
#   STRUCTURED_OUTPUT    claude_review の structured_output（JSON 文字列、空可）
#   DECIDED_EVENT        decide-event.sh の出力（APPROVE / REQUEST_CHANGES / COMMENT、デフォルト COMMENT）
#   HEAD_SHA             PR の HEAD commit SHA（必須）
#   PR_NUMBER            PR 番号（必須）
#   REPO                 owner/repo（必須）
#   REVIEW_STATUS        normal / skipped / paused / draft（デフォルト normal）
#   TOOL_FAILURES        外部ツール失敗テキスト（空可、空でなければ WARNING callout に展開）
#   RUN_ID               GitHub Actions run id（空可、Recent review info / Run configuration 用、Issue #226）
#   COMMITS_JSON         PR commits 配列の 1 行 JSON（空可、Recent review info / Commits 用、Issue #226）
#   FILES_SELECTED_JSON  処理対象ファイル一覧の 1 行 JSON 配列（空可、Recent review info / Files selected 用、Issue #226）
#   FILES_IGNORED_JSON   除外ファイル一覧の 1 行 JSON 配列（空可、Recent review info / Files with no reviewable changes 用、Issue #226）
#
# 出力: 標準出力に sticky 本文 markdown 全体。
#
# 責務:
#   - 入力 jq 解析 + テンプレ整形のみ。
#   - schema validation は upstream（claude-code-action --json-schema + post-bundled-review.sh の jq -e）に委ねる。
#   - POST / PATCH / DELETE は post-sticky-comment.sh の責務（本スクリプトでは行わない）。
#   - STRUCTURED_OUTPUT="" は正常入力として扱う（skip-mark 経路を内部分岐で吸収、別スクリプトを作らない）。
#   - Recent review info 系 env が全て空なら該当セクション自体を非出力（既存テスト Case 1-6 の後方互換）。

set -euo pipefail

: "${HEAD_SHA:?HEAD_SHA must be set}"
: "${PR_NUMBER:?PR_NUMBER must be set}"
: "${REPO:?REPO must be set}"
STRUCTURED_OUTPUT="${STRUCTURED_OUTPUT:-}"
DECIDED_EVENT="${DECIDED_EVENT:-COMMENT}"
REVIEW_STATUS="${REVIEW_STATUS:-normal}"
TOOL_FAILURES="${TOOL_FAILURES:-}"
RUN_ID="${RUN_ID:-}"
COMMITS_JSON="${COMMITS_JSON:-}"
FILES_SELECTED_JSON="${FILES_SELECTED_JSON:-}"
FILES_IGNORED_JSON="${FILES_IGNORED_JSON:-}"

printf '%s\n' "<!-- This is an auto-generated comment: sticky-summary by vibehawk -->"
printf '%s\n' "<!-- vibehawk:sticky -->"
printf '%s\n' "<!-- vibehawk:sha=${HEAD_SHA} -->"
printf '\n'

# Recent review info セクション（CodeRabbit 模倣、Issue #226）。
# Recent review info 系 env が全て空なら非出力（既存 Case 1-6 の後方互換）。
if [ -n "$RUN_ID" ] || [ -n "$COMMITS_JSON" ] || [ -n "$FILES_SELECTED_JSON" ] || [ -n "$FILES_IGNORED_JSON" ]; then
  printf '<details>\n<summary>ℹ️ Recent review info</summary>\n\n'

  # ⚙️ Run configuration（RUN_ID が非空時のみ）
  if [ -n "$RUN_ID" ]; then
    printf '<details>\n<summary>⚙️ Run configuration</summary>\n\n'
    printf '| 項目 | 値 |\n'
    printf '|---|---|\n'
    printf '| Config path | `.vibehawk.yaml` |\n'
    printf '| Review profile | vibehawk fixed |\n'
    printf '| Plan | OSS |\n'
    printf '| Run ID | %s |\n' "$RUN_ID"
    printf '\n</details>\n\n'
  fi

  # 📥 Commits（COMMITS_JSON が valid な非空配列の時のみ）
  if [ -n "$COMMITS_JSON" ]; then
    commits_count=$(printf '%s' "$COMMITS_JSON" | jq -r 'length // 0')
    if [ "${commits_count:-0}" -gt 0 ]; then
      first_sha=$(printf '%s' "$COMMITS_JSON" | jq -r '.[0].sha // ""')
      last_sha=$(printf '%s' "$COMMITS_JSON" | jq -r '.[-1].sha // ""')
      first_short=$(printf '%s' "$first_sha" | cut -c1-7)
      last_short=$(printf '%s' "$last_sha" | cut -c1-7)
      printf '<details>\n<summary>📥 Commits</summary>\n\n'
      printf 'Reviewing files that changed from the base of the PR and between %s and %s.\n' "$first_short" "$last_short"
      printf '\n</details>\n\n'
    fi
  fi

  # 📒 Files selected for processing (N)（FILES_SELECTED_JSON が valid な配列の時のみ）
  if [ -n "$FILES_SELECTED_JSON" ]; then
    selected_count=$(printf '%s' "$FILES_SELECTED_JSON" | jq -r 'length // 0')
    printf '<details>\n<summary>📒 Files selected for processing (%s)</summary>\n\n' "${selected_count:-0}"
    if [ "${selected_count:-0}" -gt 0 ]; then
      printf '%s' "$FILES_SELECTED_JSON" | jq -r '.[] | "- `" + . + "`"'
      printf '\n'
    fi
    printf '\n</details>\n\n'
  fi

  # 💤 Files with no reviewable changes (N)（FILES_IGNORED_JSON が valid な配列の時のみ）
  if [ -n "$FILES_IGNORED_JSON" ]; then
    ignored_count=$(printf '%s' "$FILES_IGNORED_JSON" | jq -r 'length // 0')
    printf '<details>\n<summary>💤 Files with no reviewable changes (%s)</summary>\n\n' "${ignored_count:-0}"
    if [ "${ignored_count:-0}" -gt 0 ]; then
      printf '%s' "$FILES_IGNORED_JSON" | jq -r '.[] | "- `" + . + "`"'
      printf '\n'
    fi
    printf '\n</details>\n\n'
  fi

  printf '</details>\n\n'
fi

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
    display_count="$findings_count"
    if [ "$display_count" -gt 10 ]; then
      display_count=10
    fi
    printf '### 🚨 主要指摘（上位 %s 件）\n\n' "${display_count}"
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
