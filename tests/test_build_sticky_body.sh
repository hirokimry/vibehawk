#!/usr/bin/env bash
# Issue #219 — build-sticky-body.sh の出力検証
#
# scripts/ci/vibehawk-review/build-sticky-body.sh を環境変数組み合わせで実行し、
# 期待した markdown セクション・マーカー・JSON が出力されるかを 6 ケースで検証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/build-sticky-body.sh"

PASSED=0
FAILED=0

pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  FAILED=$((FAILED + 1))
}

if [[ ! -x "$SCRIPT" ]]; then
  fail "${SCRIPT} が実行可能でない"
  exit 1
fi

run_build() {
  HEAD_SHA="${HEAD_SHA:-abc123}" \
  PR_NUMBER="${PR_NUMBER:-219}" \
  REPO="${REPO:-hirokimry/vibehawk}" \
  STRUCTURED_OUTPUT="${STRUCTURED_OUTPUT:-}" \
  DECIDED_EVENT="${DECIDED_EVENT:-COMMENT}" \
  REVIEW_STATUS="${REVIEW_STATUS:-normal}" \
  TOOL_FAILURES="${TOOL_FAILURES:-}" \
    bash "$SCRIPT"
}

echo "Case 1: 先頭 3 マーカーが出力される"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"テスト","commit_id":"abc","comments":[]}' run_build)
if grep -qF '<!-- This is an auto-generated comment: sticky-summary by vibehawk -->' <<< "$out" \
  && grep -qF '<!-- vibehawk:sticky -->' <<< "$out" \
  && grep -qF '<!-- vibehawk:sha=abc123 -->' <<< "$out"; then
  pass "Case 1"
else
  fail "Case 1: 先頭 3 マーカーが揃わない"
fi

echo "Case 2: severity 0 件で 0/0/0/0/0 表"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[]}' run_build)
if grep -qF '| 0 | 0 | 0 | 0 | 0 |' <<< "$out"; then
  pass "Case 2"
else
  fail "Case 2: 0/0/0/0/0 表が見つからない"
fi

echo "Case 3: 🔴×2 / 🟠×1 で Critical=2 / Major=1"
comments='[{"path":"a","line":1,"body":"🔴 1"},{"path":"b","line":2,"body":"🔴 2"},{"path":"c","line":3,"body":"🟠 3"}]'
out=$(STRUCTURED_OUTPUT="{\"event\":\"COMMENT\",\"body\":\"x\",\"commit_id\":\"abc\",\"comments\":${comments}}" run_build)
if grep -qF '| 2 | 1 | 0 | 0 | 0 |' <<< "$out"; then
  pass "Case 3"
else
  fail "Case 3: severity カウントが期待値と一致しない"
fi

echo "Case 4: REVIEW_STATUS=skipped で NOTE callout + レビュー対象なし文言"
out=$(REVIEW_STATUS=skipped STRUCTURED_OUTPUT='' run_build)
if grep -qF '> [!NOTE]' <<< "$out" && grep -qF 'レビュー対象なし' <<< "$out"; then
  pass "Case 4"
else
  fail "Case 4: NOTE callout または skipped 文言が出ない"
fi

echo "Case 5: TOOL_FAILURES 非空で WARNING callout"
out=$(TOOL_FAILURES='ESLint skipped: no config' STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[]}' run_build)
if grep -qF '> [!WARNING]' <<< "$out" && grep -qF 'ESLint skipped' <<< "$out"; then
  pass "Case 5"
else
  fail "Case 5: WARNING callout または tool failure 文言が出ない"
fi

echo "Case 6: <!-- vibehawk:state ... --> が valid JSON"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[]}' DECIDED_EVENT=REQUEST_CHANGES run_build)
state_json=$(grep -oE '<!-- vibehawk:state .* -->' <<< "$out" | sed -E 's/^<!-- vibehawk:state //; s/ -->$//')
if [[ -n "$state_json" ]] && echo "$state_json" | jq -e '.last_sha and .decided_event and .severity and .timestamp' > /dev/null; then
  pass "Case 6"
else
  fail "Case 6: state JSON が valid でない（抽出 = ${state_json}）"
fi

echo "Case 7: Issue #226 — env 4 種が空で Recent review info セクションが出力されない（後方互換）"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"テスト","commit_id":"abc","comments":[]}' run_build)
if ! grep -qF 'ℹ️ Recent review info' <<< "$out"; then
  pass "Case 7"
else
  fail "Case 7: env 未設定でも Recent review info セクションが出力されている（既存テスト破壊）"
fi

echo "Case 8: Issue #226 — env 4 種が揃うと Recent review info + 4 サブセクションが含まれる"
out=$(RUN_ID=12345 \
  COMMITS_JSON='[{"sha":"abc1234567"},{"sha":"def4567890"}]' \
  FILES_SELECTED_JSON='["a.sh","b.ts"]' \
  FILES_IGNORED_JSON='["package-lock.json"]' \
  STRUCTURED_OUTPUT='{"event":"COMMENT","body":"テスト","commit_id":"abc","comments":[]}' \
  run_build)
if grep -qF 'ℹ️ Recent review info' <<< "$out" \
  && grep -qF '⚙️ Run configuration' <<< "$out" \
  && grep -qF '📥 Commits' <<< "$out" \
  && grep -qF '📒 Files selected for processing (2)' <<< "$out" \
  && grep -qF '💤 Files with no reviewable changes (1)' <<< "$out" \
  && grep -qF '| Run ID | 12345 |' <<< "$out" \
  && grep -qF 'abc1234 and def4567' <<< "$out"; then
  pass "Case 8"
else
  fail "Case 8: Recent review info セクションまたはサブセクション 4 種が揃わない"
fi

echo "Case 9: Issue #226 — FILES_IGNORED_JSON に複数ファイルがあれば全件列挙される"
out=$(RUN_ID=99 \
  FILES_IGNORED_JSON='["package-lock.json","bun.lockb"]' \
  STRUCTURED_OUTPUT='' \
  run_build)
if grep -qF '💤 Files with no reviewable changes (2)' <<< "$out" \
  && grep -qF '`package-lock.json`' <<< "$out" \
  && grep -qF '`bun.lockb`' <<< "$out"; then
  pass "Case 9"
else
  fail "Case 9: ignored ファイル一覧が期待通りに表示されない"
fi

echo "Case 10: Issue #227 / #237 — walkthrough_narrative + changes_table（グループ構造）→ 📝 Walkthrough セクションが含まれる"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"narrative 本文","changes_table":[{"group":"G1","changes":[{"files":["a.sh"],"summary":"S1"}]}]}' run_build)
if grep -qF '📝 Walkthrough' <<< "$out" \
  && grep -qF '## Walkthrough' <<< "$out" \
  && grep -qF 'narrative 本文' <<< "$out" \
  && grep -qF '## Changes' <<< "$out" \
  && grep -qF '**G1**' <<< "$out" \
  && grep -qF '| File(s) | Summary |' <<< "$out" \
  && grep -qF '| a.sh | S1 |' <<< "$out"; then
  pass "Case 10"
else
  fail "Case 10: Walkthrough セクションまたは Changes グループテーブルが期待通りに展開されない"
fi

echo "Case 11: Issue #227 — walkthrough_narrative が 1000 文字でも切り詰めなしで全文表示される"
long_text=$(printf 'A%.0s' $(seq 1 1000))
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"'"${long_text}"'","changes_table":[]}' run_build)
# 既存「📝 概要」セクションが撤去されており、「…」省略記号が出ない（200 文字切り詰め撤去確認）
if grep -qF "$long_text" <<< "$out" && ! grep -qF '### 📝 概要' <<< "$out"; then
  pass "Case 11"
else
  fail "Case 11: 切り詰めなしで 1000 文字が表示されていないか、旧『📝 概要』が撤去されていない"
fi

echo "Case 12: Issue #237 — changes_table 2 グループ計 3 変更 → グループ別テーブルに 3 行表示される"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[{"group":"G1","changes":[{"files":["f1"],"summary":"s1"},{"files":["f2"],"summary":"s2"}]},{"group":"G2","changes":[{"files":["f3"],"summary":"s3"}]}]}' run_build)
# 3 行のデータ行が含まれていることを確認（| f1 | s1 | 形式）
row_count=$(grep -cE '^\| f[123] \| s[123] \|$' <<< "$out" || true)
if [[ "$row_count" -eq 3 ]]; then
  pass "Case 12"
else
  fail "Case 12: changes_table 3 行が期待通り表示されない（row_count=$row_count）"
fi

echo "Case 13: Issue #227 — walkthrough_narrative 欠落 + changes_table 空 → Walkthrough セクション非出力（後方互換）"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[]}' run_build)
if ! grep -qF '📝 Walkthrough' <<< "$out"; then
  pass "Case 13"
else
  fail "Case 13: walkthrough_narrative 欠落でも Walkthrough セクションが出ている（後方互換破壊）"
fi

echo "Case 14: Issue #228 — review_effort difficulty 3 → 🎯 3 (Moderate) | ⏱️ ~M minutes 表示"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[],"review_effort":{"difficulty":3,"minutes":25}}' run_build)
if grep -qF '## 🎯 3 (Moderate) | ⏱️ ~25 minutes' <<< "$out"; then
  pass "Case 14"
else
  fail "Case 14: review_effort 行が期待形式で表示されない"
fi

echo "Case 15: Issue #228 — RELATED_PRS_JSON に 2 件 → ## Possibly related PRs に列挙、0 件は『No related PRs found.』"
out=$(RELATED_PRS_JSON='[{"number":150,"title":"sticky 機能拡張"},{"number":160,"title":"レビュー仕様変更"}]' \
  STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[],"review_effort":{"difficulty":2,"minutes":10}}' \
  run_build)
if grep -qF '## Possibly related PRs' <<< "$out" \
  && grep -qF -e '- #150: sticky 機能拡張' <<< "$out" \
  && grep -qF -e '- #160: レビュー仕様変更' <<< "$out"; then
  pass "Case 15a (列挙)"
else
  fail "Case 15a: Possibly related PRs の列挙が期待通りでない"
fi
out_empty=$(RELATED_PRS_JSON='[]' \
  STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[],"review_effort":{"difficulty":1,"minutes":5}}' \
  run_build)
if grep -qF 'No related PRs found.' <<< "$out_empty"; then
  pass "Case 15b (0 件 fallback)"
else
  fail "Case 15b: 0 件時の『No related PRs found.』が出ない"
fi

echo "Case 16: Issue #228 — SUGGESTED_REVIEWERS_JSON に 2 名 → ## Suggested reviewers に列挙、0 名は『No suggested reviewers.』"
out=$(SUGGESTED_REVIEWERS_JSON='["hirokimry","alice"]' \
  STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[],"review_effort":{"difficulty":3,"minutes":20}}' \
  run_build)
if grep -qF '## Suggested reviewers' <<< "$out" \
  && grep -qF -e '- @hirokimry' <<< "$out" \
  && grep -qF -e '- @alice' <<< "$out"; then
  pass "Case 16a (列挙)"
else
  fail "Case 16a: Suggested reviewers の列挙が期待通りでない"
fi
out_empty=$(SUGGESTED_REVIEWERS_JSON='[]' \
  STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[],"review_effort":{"difficulty":1,"minutes":5}}' \
  run_build)
if grep -qF 'No suggested reviewers.' <<< "$out_empty"; then
  pass "Case 16b (0 名 fallback)"
else
  fail "Case 16b: 0 名時の『No suggested reviewers.』が出ない"
fi

echo "Case 17: Issue #229 — Pre-merge checks 5 項目すべて passed → ✅ 4 passed (skipped 1 件) summary"
out=$(PRE_MERGE_TITLE_STATUS="passed" PRE_MERGE_TITLE_EXPLANATION="OK" \
      PRE_MERGE_DESCRIPTION_STATUS="passed" PRE_MERGE_DESCRIPTION_EXPLANATION="OK" \
      PRE_MERGE_DOCSTRING_STATUS="skipped" PRE_MERGE_DOCSTRING_EXPLANATION="N/A" \
      STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[],"review_effort":{"difficulty":2,"minutes":10},"pre_merge_checks":{"linked_issues_check":{"status":"passed","explanation":"A"},"out_of_scope_check":{"status":"passed","explanation":"B"}}}' \
      run_build)
if grep -qF '🚥 Pre-merge checks | ✅ 4 passed' <<< "$out" \
  && grep -qF '| Title check | ✅ passed' <<< "$out" \
  && grep -qF '| Linked Issues check | ✅ passed' <<< "$out" \
  && grep -qF '| Docstring Coverage | ⏭️ skipped' <<< "$out"; then
  pass "Case 17"
else
  fail "Case 17: Pre-merge checks の summary または 5 項目表示が期待通りでない"
fi

echo "Case 18: Issue #229 — Pre-merge checks に failed 1 件あり → ⚠️ 1 failed summary"
out=$(PRE_MERGE_TITLE_STATUS="failed" PRE_MERGE_TITLE_EXPLANATION="形式違反" \
      PRE_MERGE_DESCRIPTION_STATUS="passed" PRE_MERGE_DESCRIPTION_EXPLANATION="OK" \
      PRE_MERGE_DOCSTRING_STATUS="skipped" PRE_MERGE_DOCSTRING_EXPLANATION="N/A" \
      STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[],"review_effort":{"difficulty":2,"minutes":10},"pre_merge_checks":{"linked_issues_check":{"status":"passed","explanation":"A"},"out_of_scope_check":{"status":"passed","explanation":"B"}}}' \
      run_build)
if grep -qF '🚥 Pre-merge checks | ⚠️ 1 failed' <<< "$out" \
  && grep -qF '| Title check | ❌ failed' <<< "$out"; then
  pass "Case 18"
else
  fail "Case 18: failed 1 件時の summary 切替が期待通りでない"
fi

echo "Case 19: Issue #241 — 英語見出し ## 🦅 vibehawk Review Summary が一番上（Recent review info より上）に来る"
out=$(RUN_ID=12345 \
  STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[]}' \
  run_build)
heading_line=$(grep -nF '## 🦅 vibehawk Review Summary' <<< "$out" | head -1 | cut -d: -f1)
recent_line=$(grep -nF 'ℹ️ Recent review info' <<< "$out" | head -1 | cut -d: -f1)
if [[ -n "$heading_line" && -n "$recent_line" && "$heading_line" -lt "$recent_line" ]] \
  && ! grep -qF 'vibehawk レビューサマリ' <<< "$out"; then
  pass "Case 19"
else
  fail "Case 19: 英語見出しが最上部に来ていない（heading=${heading_line} recent=${recent_line}）または旧日本語見出しが残存"
fi

echo "Case 20: Issue #241 — severity 集計が Walkthrough セクションより前に来る（出力順の回帰検知）"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[{"group":"G1","changes":[{"files":["a.sh"],"summary":"s1"}]}]}' run_build)
severity_line=$(grep -nF '📊 severity 集計' <<< "$out" | head -1 | cut -d: -f1)
walkthrough_line=$(grep -nF '📝 Walkthrough' <<< "$out" | head -1 | cut -d: -f1)
if [[ -n "$severity_line" && -n "$walkthrough_line" && "$severity_line" -lt "$walkthrough_line" ]]; then
  pass "Case 20"
else
  fail "Case 20: severity が Walkthrough より後に来ている（severity=${severity_line} walkthrough=${walkthrough_line}）"
fi

echo "Case 21: Issue #236 — severity 集計が <details> 折り畳みに格納され、ベタ置き h3 が消える"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[]}' run_build)
if grep -qF '<summary>📊 severity 集計</summary>' <<< "$out" \
  && grep -qF '</details>' <<< "$out" \
  && ! grep -qF '### 📊 severity 集計' <<< "$out"; then
  pass "Case 21"
else
  fail "Case 21: severity 集計が <details> に折り畳まれていない、または旧 h3 ベタ置きが残存"
fi

echo "Case 22: Issue #237 — changes_table 複数グループ → グループごとの太字見出しが出る"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[{"group":"Pre-merge 実装","changes":[{"files":["a.sh"],"summary":"s1"}]},{"group":"テスト追加","changes":[{"files":["t.sh"],"summary":"s2"}]}]}' run_build)
if grep -qF '**Pre-merge 実装**' <<< "$out" \
  && grep -qF '**テスト追加**' <<< "$out"; then
  pass "Case 22"
else
  fail "Case 22: changes_table のグループ別太字見出しが出ない"
fi

echo "Case 23: Issue #237 — Changes セルの | と改行がエスケープされ表崩れしない（CodeRabbit 指摘）"
out=$(STRUCTURED_OUTPUT='{"event":"COMMENT","body":"x","commit_id":"abc","comments":[],"walkthrough_narrative":"n","changes_table":[{"group":"G","changes":[{"files":["a.sh"],"summary":"foo | bar\nbaz"}]}]}' run_build)
if grep -qF 'foo \| bar<br>baz' <<< "$out"; then
  pass "Case 23"
else
  fail "Case 23: セルの | / 改行がエスケープされていない"
fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
