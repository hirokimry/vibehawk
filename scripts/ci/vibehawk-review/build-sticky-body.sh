#!/usr/bin/env bash
# 用途: vibehawk PR sticky walkthrough コメントの body markdown 文字列を生成する（Issue #219 / #226 / #241）
#
# 入力（環境変数）:
#   STRUCTURED_OUTPUT    claude_review の structured_output（JSON 文字列、空可）
#   DECIDED_EVENT        decide-event.sh の出力（APPROVE / REQUEST_CHANGES / COMMENT、デフォルト COMMENT）
#   HEAD_SHA             PR の HEAD commit SHA（必須）
#   PR_NUMBER            PR 番号（必須）
#   REPO                 owner/repo（必須）
#   REVIEW_STATUS        normal / skipped / paused / draft（デフォルト normal）
#   TOOL_FAILURES        外部ツール失敗テキスト（空可、空でなければ WARNING callout に展開）
#   RUN_ID                    GitHub Actions run id（空可、Recent review info / Run configuration 用、Issue #226）
#   COMMITS_JSON              PR commits 配列の 1 行 JSON（空可、Recent review info / Commits 用、Issue #226）
#   FILES_SELECTED_JSON       処理対象ファイル一覧の 1 行 JSON 配列（空可、Recent review info / Files selected 用、Issue #226）
#   FILES_IGNORED_JSON        除外ファイル一覧の 1 行 JSON 配列（空可、Recent review info / Files with no reviewable changes 用、Issue #226）
#   RELATED_PRS_JSON          関連 PR の 1 行 JSON 配列（空可、Possibly related PRs 用、Issue #228）
#   SUGGESTED_REVIEWERS_JSON  推奨レビュワーの 1 行 JSON 配列（空可、Suggested reviewers 用、Issue #228）
#
# 出力: 標準出力に sticky 本文 markdown 全体。
#
# 責務:
#   - 入力 jq 解析 + テンプレ整形のみ。
#   - schema validation は upstream（claude-code-action --json-schema + post-bundled-review.sh の jq -e）に委ねる。
#   - POST / PATCH / DELETE は post-sticky-comment.sh の責務（本スクリプトでは行わない）。
#   - STRUCTURED_OUTPUT="" は正常入力として扱う（skip-mark 経路を内部分岐で吸収、別スクリプトを作らない）。
#   - Recent review info 系 env が全て空なら該当セクション自体を非出力（既存テスト Case 1-6 の後方互換）。
#
# Issue #241: 英語タイトル `## 🦅 vibehawk Review Summary` をコメントの一番上（Recent review info より上）に置き、
#   後続の全セクション（Recent review info / severity 集計 / 主要指摘 / Walkthrough / Pre-merge）を配下に束ねる。
#   タイトル行だけ英語、配下の本文・各セクションは日本語のまま。

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
RELATED_PRS_JSON="${RELATED_PRS_JSON:-}"
SUGGESTED_REVIEWERS_JSON="${SUGGESTED_REVIEWERS_JSON:-}"
PRE_MERGE_TITLE_STATUS="${PRE_MERGE_TITLE_STATUS:-}"
PRE_MERGE_TITLE_EXPLANATION="${PRE_MERGE_TITLE_EXPLANATION:-}"
PRE_MERGE_DESCRIPTION_STATUS="${PRE_MERGE_DESCRIPTION_STATUS:-}"
PRE_MERGE_DESCRIPTION_EXPLANATION="${PRE_MERGE_DESCRIPTION_EXPLANATION:-}"
PRE_MERGE_DOCSTRING_STATUS="${PRE_MERGE_DOCSTRING_STATUS:-}"
PRE_MERGE_DOCSTRING_EXPLANATION="${PRE_MERGE_DOCSTRING_EXPLANATION:-}"

printf '%s\n' "<!-- This is an auto-generated comment: sticky-summary by vibehawk -->"
printf '%s\n' "<!-- vibehawk:sticky -->"
printf '%s\n' "<!-- vibehawk:sha=${HEAD_SHA} -->"
printf '\n'

# Issue #241: 英語タイトルをコメントの一番上に置き、後続の全セクションを束ねる容れ物にする。
# タイトル行だけ英語、配下の本文・各セクションは日本語のまま。
printf '## 🦅 vibehawk Review Summary\n\n'

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

# 📊 severity 集計（Issue #236: <details> 折り畳みで他セクションと質感を統一、ベタ置きをやめる）
printf '<details>\n<summary>📊 severity 集計</summary>\n\n'
printf '| 🔴 Critical | 🟠 Major | 🟡 Minor | 🔵 Trivial | ⚪ Info |\n'
printf '|---|---|---|---|---|\n'
printf '%s' "$severity_counts" | jq -r '"| " + (.critical|tostring) + " | " + (.major|tostring) + " | " + (.minor|tostring) + " | " + (.trivial|tostring) + " | " + (.info|tostring) + " |"'
printf '\n</details>\n\n'

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

# 📝 Walkthrough セクション（CodeRabbit 互換、Issue #227 / #228）
# Claude が schema で必須化された walkthrough_narrative + changes_table + review_effort を返すため、
# それらと workflow step 取得の related_prs / suggested_reviewers を
# <details><summary>📝 Walkthrough</summary> で折り畳んで展開する。
# 後方互換: 全フィールド欠落時はセクション非出力。
if [ -n "$STRUCTURED_OUTPUT" ] || [ -n "$RELATED_PRS_JSON" ] || [ -n "$SUGGESTED_REVIEWERS_JSON" ]; then
  walkthrough_narrative=""
  changes_table_json="[]"
  changes_count=0
  review_effort_difficulty=""
  review_effort_minutes=""

  if [ -n "$STRUCTURED_OUTPUT" ]; then
    walkthrough_narrative=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -r '.walkthrough_narrative // ""')
    changes_table_json=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -c '.changes_table // []')
    changes_count=$(printf '%s' "$changes_table_json" | jq -r 'length // 0')
    review_effort_difficulty=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -r '.review_effort.difficulty // empty')
    review_effort_minutes=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -r '.review_effort.minutes // empty')
  fi

  related_prs_count=0
  if [ -n "$RELATED_PRS_JSON" ]; then
    related_prs_count=$(printf '%s' "$RELATED_PRS_JSON" | jq -r 'length // 0' 2>/dev/null || printf '0')
  fi

  suggested_reviewers_count=0
  if [ -n "$SUGGESTED_REVIEWERS_JSON" ]; then
    suggested_reviewers_count=$(printf '%s' "$SUGGESTED_REVIEWERS_JSON" | jq -r 'length // 0' 2>/dev/null || printf '0')
  fi

  # いずれかの要素があれば Walkthrough セクションを開く
  if [ -n "$walkthrough_narrative" ] || [ "${changes_count:-0}" -gt 0 ] \
    || [ -n "$review_effort_difficulty" ] \
    || [ -n "$RELATED_PRS_JSON" ] || [ -n "$SUGGESTED_REVIEWERS_JSON" ]; then
    printf '<details>\n<summary>📝 Walkthrough</summary>\n\n'

    if [ -n "$walkthrough_narrative" ]; then
      printf '## Walkthrough\n\n%s\n\n' "$walkthrough_narrative"
    fi

    # Issue #237: Changes を意味グループごとに「太字見出し + 小テーブル」へ分割する。
    # 各グループ = {group, changes:[{files, summary}]}。大型 PR でも領域別に 30 秒でスキャンできる。
    if [ "${changes_count:-0}" -gt 0 ]; then
      printf '## Changes\n\n'
      # セル内の `|` / 改行は Markdown テーブルを壊すためエスケープする（Issue #237 / CodeRabbit 指摘）。
      printf '%s\n\n' "$(printf '%s' "$changes_table_json" | jq -r '
        def esc_cell:
          tostring
          | gsub("\\|"; "\\|")
          | gsub("\\r?\\n"; "<br>");
        [ .[]
          | "**" + (.group | tostring | gsub("\\r?\\n"; " ")) + "**\n\n| File(s) | Summary |\n|---|---|\n"
            + ([.changes[] | "| " + (.files | map(esc_cell) | join(", ")) + " | " + (.summary | esc_cell) + " |"] | join("\n"))
        ] | join("\n\n")
      ')"
    fi

    # 推定レビュー労力（Issue #228 / #238）。値を見出しにせず名詞見出し + 🎯 行で並びを揃える。
    if [ -n "$review_effort_difficulty" ] && [ -n "$review_effort_minutes" ]; then
      case "$review_effort_difficulty" in
        1) effort_label="Trivial" ;;
        2) effort_label="Easy" ;;
        3) effort_label="Moderate" ;;
        4) effort_label="Complex" ;;
        5) effort_label="Very Complex" ;;
        *) effort_label="Unknown" ;;
      esac
      printf '## Estimated code review effort\n\n'
      printf '🎯 %s (%s) | ⏱️ ~%s minutes\n\n' "$review_effort_difficulty" "$effort_label" "$review_effort_minutes"
    fi

    # 🔗 Possibly related PRs（Issue #228、workflow step 取得）
    if [ -n "$RELATED_PRS_JSON" ]; then
      printf '## Possibly related PRs\n\n'
      if [ "${related_prs_count:-0}" -gt 0 ]; then
        printf '%s' "$RELATED_PRS_JSON" | jq -r '
          .[] | "- #" + (.number | tostring) + ": " + .title
        '
        printf '\n'
      else
        printf 'No related PRs found.\n\n'
      fi
    fi

    # 👥 Suggested reviewers（Issue #228、workflow step 取得）
    if [ -n "$SUGGESTED_REVIEWERS_JSON" ]; then
      printf '## Suggested reviewers\n\n'
      if [ "${suggested_reviewers_count:-0}" -gt 0 ]; then
        printf '%s' "$SUGGESTED_REVIEWERS_JSON" | jq -r '
          .[] | "- @" + .
        '
        printf '\n'
      else
        printf 'No suggested reviewers.\n\n'
      fi
    fi

    printf '</details>\n\n'
  fi
fi

# 🚥 Pre-merge checks セクション（CodeRabbit 互換、Issue #229）
# 5 項目: Title check / Description check / Linked Issues check / Out of Scope Changes check / Docstring Coverage
# - Title / Description / Docstring: workflow step 機械判定（env で渡される）
# - Linked Issues / Out of Scope: Claude prompt 判定（STRUCTURED_OUTPUT の pre_merge_checks）
# - 全 5 項目の status を集計して summary に passed/failed 件数を表示
if [ -n "$PRE_MERGE_TITLE_STATUS" ] || [ -n "$PRE_MERGE_DESCRIPTION_STATUS" ] || [ -n "$STRUCTURED_OUTPUT" ]; then
  linked_status=""
  linked_explanation=""
  out_of_scope_status=""
  out_of_scope_explanation=""
  if [ -n "$STRUCTURED_OUTPUT" ]; then
    linked_status=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -r '.pre_merge_checks.linked_issues_check.status // ""')
    linked_explanation=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -r '.pre_merge_checks.linked_issues_check.explanation // ""')
    out_of_scope_status=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -r '.pre_merge_checks.out_of_scope_check.status // ""')
    out_of_scope_explanation=$(printf '%s' "$STRUCTURED_OUTPUT" | jq -r '.pre_merge_checks.out_of_scope_check.explanation // ""')
  fi

  # 5 項目の status を集計
  passed_count=0
  failed_count=0
  for s in "$PRE_MERGE_TITLE_STATUS" "$PRE_MERGE_DESCRIPTION_STATUS" "$linked_status" "$out_of_scope_status" "$PRE_MERGE_DOCSTRING_STATUS"; do
    case "$s" in
      passed) passed_count=$((passed_count + 1)) ;;
      failed) failed_count=$((failed_count + 1)) ;;
    esac
  done

  # summary 表記: failed が 1 件以上なら ⚠️ N failed、それ以外は ✅ N passed
  if [ "$failed_count" -gt 0 ]; then
    summary_label="⚠️ ${failed_count} failed"
  else
    summary_label="✅ ${passed_count} passed"
  fi

  printf '<details>\n<summary>🚥 Pre-merge checks | %s</summary>\n\n' "$summary_label"
  printf '| Check | Status | Explanation |\n'
  printf '|---|---|---|\n'
  # 各 status を絵文字に変換
  status_icon() {
    case "$1" in
      passed) printf '✅ passed' ;;
      failed) printf '❌ failed' ;;
      skipped) printf '⏭️ skipped' ;;
      *) printf '— unknown' ;;
    esac
  }
  printf '| Title check | %s | %s |\n' "$(status_icon "$PRE_MERGE_TITLE_STATUS")" "${PRE_MERGE_TITLE_EXPLANATION:-—}"
  printf '| Description check | %s | %s |\n' "$(status_icon "$PRE_MERGE_DESCRIPTION_STATUS")" "${PRE_MERGE_DESCRIPTION_EXPLANATION:-—}"
  printf '| Linked Issues check | %s | %s |\n' "$(status_icon "$linked_status")" "${linked_explanation:-—}"
  printf '| Out of Scope Changes check | %s | %s |\n' "$(status_icon "$out_of_scope_status")" "${out_of_scope_explanation:-—}"
  printf '| Docstring Coverage | %s | %s |\n' "$(status_icon "$PRE_MERGE_DOCSTRING_STATUS")" "${PRE_MERGE_DOCSTRING_EXPLANATION:-—}"
  printf '\n</details>\n\n'
fi

# Issue #227: 旧「📖 詳細レビュー」（body_full 残り全体の折り畳み）は撤去。
# walkthrough_narrative + changes_table が冒頭の「📝 Walkthrough」セクションで同等以上の情報を持つため。

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
