#!/usr/bin/env bash
# .github/scripts/load-vibehawk-prompt.sh の単体テスト
#
# - envsubst が 14 個の env を全部展開すること
# - GITHUB_OUTPUT に multi-line heredoc 形式で書き出されること
# - PROMPT_FILE 不在時に exit 1 + error メッセージ
# - sensitive な未指定 env (例: ANTHROPIC_API_KEY) が展開されないこと（whitelist 動作）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/load-vibehawk-prompt.sh"
DEFAULT_PROMPT="${REPO_ROOT}/.github/prompts/vibehawk-review.md"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

if [[ ! -x "$SCRIPT" ]]; then
  fail "${SCRIPT} が実行可能でない"
  exit 1
fi

if [[ ! -f "$DEFAULT_PROMPT" ]]; then
  fail ".github/prompts/vibehawk-review.md が存在しない"
  exit 1
fi

TMP_OUTPUTS=()
cleanup() {
  for f in "${TMP_OUTPUTS[@]+"${TMP_OUTPUTS[@]}"}"; do
    rm -f "$f" || true
  done
}
trap cleanup EXIT

run_load() {
  local out
  out="$(mktemp)"
  TMP_OUTPUTS+=("$out")
  cd "$REPO_ROOT"
  GITHUB_OUTPUT="$out" \
    REPO="${REPO:-test/repo}" \
    PR_NUMBER="${PR_NUMBER:-235}" \
    HEAD_SHA="${HEAD_SHA:-abc1234}" \
    BASE_REF="${BASE_REF:-main}" \
    INCREMENTAL_MODE="${INCREMENTAL_MODE:-false}" \
    EXISTING_COMMENT_ID="${EXISTING_COMMENT_ID:-}" \
    PREV_SHA="${PREV_SHA:-}" \
    REVIEW_RANGE="${REVIEW_RANGE:-}" \
    CONFIG_SOURCE="${CONFIG_SOURCE:-default}" \
    LANGUAGE="${LANGUAGE:-en}" \
    FILES_COUNT="${FILES_COUNT:-10}" \
    DEPTH="${DEPTH:-full}" \
    PATH_FILTERS_JSON="${PATH_FILTERS_JSON:-[]}" \
    PATH_INSTRUCTIONS_JSON="${PATH_INSTRUCTIONS_JSON:-[]}" \
    bash "$SCRIPT" >&2
  printf '%s' "$out"
}

echo "Case 1: GITHUB_OUTPUT に content<<__VIBEHAWK_PROMPT_EOF__ heredoc が書き出される"
out_file="$(run_load)"
if head -1 "$out_file" | grep -qF 'content<<__VIBEHAWK_PROMPT_EOF__' \
  && tail -1 "$out_file" | grep -qF '__VIBEHAWK_PROMPT_EOF__'; then
  pass "Case 1"
else
  fail "Case 1: heredoc delimiter が想定通りでない"
fi

echo "Case 2: 14 個の env が全部展開されている（\${...} 残存なし）"
# heredoc delimiter 自体は __VIBEHAWK_PROMPT_EOF__ なので除外し、未展開の ${REPO} 等を grep
remaining=$(grep -E '\$\{(REPO|PR_NUMBER|HEAD_SHA|BASE_REF|INCREMENTAL_MODE|EXISTING_COMMENT_ID|PREV_SHA|REVIEW_RANGE|CONFIG_SOURCE|LANGUAGE|FILES_COUNT|DEPTH|PATH_FILTERS_JSON|PATH_INSTRUCTIONS_JSON)\}' "$out_file" || true)
if [[ -z "$remaining" ]]; then
  pass "Case 2"
else
  fail "Case 2: 未展開の env が残っている: $remaining"
fi

echo "Case 3: 個別 env の値が正しく展開される（REPO / PR_NUMBER / HEAD_SHA）"
REPO="myorg/myrepo" PR_NUMBER="999" HEAD_SHA="deadbeef" out_file="$(run_load)"
if grep -qF 'REPO: myorg/myrepo' "$out_file" \
  && grep -qF 'PR_NUMBER: 999' "$out_file" \
  && grep -qF 'HEAD_SHA: deadbeef' "$out_file"; then
  pass "Case 3"
else
  fail "Case 3: env 展開結果が期待値と一致しない"
fi

echo "Case 4: sensitive な未指定 env (ANTHROPIC_API_KEY) が展開されない（whitelist 動作）"
# プロンプトに `\${ANTHROPIC_API_KEY}` リテラルを追加した一時ファイルを使う
fake_prompt="$(mktemp)"
TMP_OUTPUTS+=("$fake_prompt")
printf 'REPO: ${REPO}\nSECRET: ${ANTHROPIC_API_KEY}\n' > "$fake_prompt"
out_file="$(mktemp)"
TMP_OUTPUTS+=("$out_file")
cd "$REPO_ROOT"
GITHUB_OUTPUT="$out_file" \
  PROMPT_FILE="$fake_prompt" \
  REPO=test/repo PR_NUMBER=1 HEAD_SHA=a BASE_REF=main \
  INCREMENTAL_MODE=false EXISTING_COMMENT_ID="" PREV_SHA="" REVIEW_RANGE="" \
  CONFIG_SOURCE=default LANGUAGE=en FILES_COUNT=10 DEPTH=full \
  PATH_FILTERS_JSON='[]' PATH_INSTRUCTIONS_JSON='[]' \
  ANTHROPIC_API_KEY="should-not-leak" \
  bash "$SCRIPT" >&2
# REPO は展開され、ANTHROPIC_API_KEY はリテラルのまま残るはず
if grep -qF 'REPO: test/repo' "$out_file" \
  && grep -qF 'SECRET: ${ANTHROPIC_API_KEY}' "$out_file" \
  && ! grep -qF 'should-not-leak' "$out_file"; then
  pass "Case 4"
else
  fail "Case 4: whitelist 動作が機能していない（ANTHROPIC_API_KEY 展開リスク）"
fi

echo "Case 5: PROMPT_FILE 不在で exit 1 + エラーメッセージ"
set +e
log_output=$(PROMPT_FILE=/nonexistent/path.md GITHUB_OUTPUT=$(mktemp) \
  REPO=x PR_NUMBER=1 HEAD_SHA=a BASE_REF=main \
  INCREMENTAL_MODE=false EXISTING_COMMENT_ID="" PREV_SHA="" REVIEW_RANGE="" \
  CONFIG_SOURCE=default LANGUAGE=en FILES_COUNT=10 DEPTH=full \
  PATH_FILTERS_JSON='[]' PATH_INSTRUCTIONS_JSON='[]' \
  bash "$SCRIPT" 2>&1)
script_exit=$?
set -e
if [[ $script_exit -ne 0 ]] && printf '%s' "$log_output" | grep -qF 'プロンプトファイルが見つかりません'; then
  pass "Case 5"
else
  fail "Case 5: exit=$script_exit, output=$log_output"
fi

echo "Case 6: inline 指摘ガイダンスが CodeRabbit 互換の 3 軸ラベルを要求している（Issue #252）"
# 3 軸ラベル（カテゴリ | severity | 労力）の指示と実例が prompt に存在することを検証する。
# severity 絵文字はラベル内に保持されるため、decide-event.sh の severity 分布カウントは壊れない。
if grep -qF '先頭行を CodeRabbit 互換の 3 軸ラベル' "$DEFAULT_PROMPT" \
  && grep -qF '_⚠️ Potential issue_ | _🟠 Major_ | _⚡ Quick win_' "$DEFAULT_PROMPT" \
  && grep -qF '⚡ Quick win' "$DEFAULT_PROMPT" \
  && grep -qF '🏗️ Heavy lift' "$DEFAULT_PROMPT"; then
  pass "Case 6"
else
  fail "Case 6: 3 軸ラベル（カテゴリ/severity/労力）のガイダンスが prompt に無い"
fi

echo "Case 7: 旧 1 軸 severity ガイダンス（先頭に severity 絵文字を 1 つ）が残っていない（Issue #252）"
if grep -qF '冒頭に必ず該当 severity の絵文字を 1 つ付ける' "$DEFAULT_PROMPT"; then
  fail "Case 7: 旧 1 軸 severity ガイダンスが残存している"
else
  pass "Case 7"
fi

echo "Case 8: inline 指摘が太字タイトル + 説明段落の 2 部構成を要求している（Issue #253）"
if grep -qF '太字タイトル + 説明段落の 2 部構成' "$DEFAULT_PROMPT" \
  && grep -qF '太字 1 行タイトル' "$DEFAULT_PROMPT"; then
  pass "Case 8"
else
  fail "Case 8: 2 部構成（太字タイトル + 説明段落）のガイダンスが prompt に無い"
fi

echo "Case 9: inline 指摘に AI 向け修正指示の <details> 折り畳みを要求している（Issue #254）"
if grep -qF '🤖 AI 向け修正指示' "$DEFAULT_PROMPT" \
  && grep -qF 'AI エージェントが修正に着手できる指示' "$DEFAULT_PROMPT"; then
  pass "Case 9"
else
  fail "Case 9: 🤖 AI 向け修正指示の折り畳みガイダンスが prompt に無い"
fi

echo "Case 11: inline 指摘の末尾に vibehawk 識別フッタを要求している（Issue #256）"
if grep -qF 'vibehawk 識別フッタ' "$DEFAULT_PROMPT" \
  && grep -qF 'vibehawk:inline' "$DEFAULT_PROMPT"; then
  pass "Case 11"
else
  fail "Case 11: vibehawk 識別フッタのガイダンスが prompt に無い"
fi

echo "Case 12: CodeRabbit フッタ文言の literal コピーを禁止している（Issue #256）"
if grep -qF 'literal コピーは出所を偽る' "$DEFAULT_PROMPT"; then
  pass "Case 12"
else
  fail "Case 12: CodeRabbit 文言 literal コピー禁止の明記が無い"
fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
