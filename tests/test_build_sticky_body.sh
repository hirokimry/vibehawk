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

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
