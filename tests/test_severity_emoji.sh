#!/usr/bin/env bash
# Issue #9: vibehawk-review.yml の prompt に含まれる severity 5 段階分類規則の検証
#
# 検証対象:
# - severity 5 段階の絵文字（🔴/🟠/🟡/🔵/⚪）が prompt に含まれる
# - CodeRabbit 公式仕様（.claude/rules/severity/coderabbit.md）に従った定義
# - inline comment 本文に severity 絵文字を冒頭付与する指示がある
# - GitHub Suggestions 構文の使用許可と「Bot 自身が commit しない」制約が明示

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

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

WORKFLOW="${REPO_ROOT}/.github/workflows/vibehawk-review.yml"

echo "=== severity 5 段階絵文字（Issue #9） ==="

declare -a severity_pairs=(
  '🔴|Critical'
  '🟠|Major'
  '🟡|Minor'
  '🔵|Trivial'
  '⚪|Info'
)

for pair in "${severity_pairs[@]}"; do
  emoji="${pair%|*}"
  label="${pair#*|}"
  if grep -F "${emoji}" "$WORKFLOW" > /dev/null && grep -F "${label}" "$WORKFLOW" > /dev/null; then
    pass "severity ${label} (${emoji}) が prompt に含まれる"
  else
    fail "severity ${label} (${emoji}) が prompt に含まれない（CodeRabbit 公式仕様準拠）"
  fi
done

echo "=== inline comment 投稿指示（Issue #9） ==="

if grep -F 'gh api -X POST' "$WORKFLOW" | grep -F 'pulls/$PR_NUMBER/comments' > /dev/null; then
  pass "inline comment 投稿コマンド (gh api -X POST .../pulls/.../comments) が prompt に含まれる"
else
  fail "inline comment 投稿コマンドが prompt に含まれない"
fi

if grep -F 'commit_id=' "$WORKFLOW" > /dev/null && \
   grep -F 'path=' "$WORKFLOW" > /dev/null && \
   grep -F 'line=' "$WORKFLOW" > /dev/null && \
   grep -F 'side=' "$WORKFLOW" > /dev/null; then
  pass "inline comment 必須フィールド（commit_id / path / line / side）が prompt に明示"
else
  fail "inline comment 必須フィールドが prompt に揃っていない"
fi

if grep -F 'severity 絵文字を 1 つ付ける' "$WORKFLOW" > /dev/null || \
   grep -F '冒頭に必ず' "$WORKFLOW" > /dev/null; then
  pass "inline comment 冒頭への severity 絵文字付与指示が prompt に含まれる"
else
  fail "inline comment への severity 絵文字付与指示が prompt に含まれない"
fi

echo "=== GitHub Suggestions 構文（Issue #9 / 5 大方針 2） ==="

if grep -F 'suggestion' "$WORKFLOW" > /dev/null && \
   grep -F 'Bot 自身は commit しない' "$WORKFLOW" > /dev/null; then
  pass "Suggestions 構文の許可と「Bot 自身は commit しない」制約が prompt に明示"
else
  fail "Suggestions 構文の制約説明が prompt に不足"
fi

echo "=== auto_resolve 制約（Issue #9） ==="

if grep -F 'resolveReviewThread' "$WORKFLOW" > /dev/null; then
  pass "auto_resolve の GraphQL mutation (resolveReviewThread) が prompt に含まれる"
else
  fail "auto_resolve の GraphQL mutation が prompt に含まれない"
fi

if grep -F '他者・他 Bot のコメントは絶対に touch しない' "$WORKFLOW" > /dev/null || \
   grep -F '他者・他 Bot のレビュースレッドには **絶対に' "$WORKFLOW" > /dev/null; then
  pass "auto_resolve の「他者・他 Bot は touch しない」制約が prompt に明示"
else
  fail "auto_resolve の他者非操作制約が prompt に不足（誤 resolve は信頼破壊）"
fi

echo "=== sticky review state（Issue #9） ==="

if grep -F 'gh pr review' "$WORKFLOW" | grep -F -- '--approve' > /dev/null && \
   grep -F 'gh pr review' "$WORKFLOW" | grep -F -- '--request-changes' > /dev/null; then
  pass "sticky review の approve / request-changes 切替指示が prompt に含まれる"
else
  fail "sticky review の approve / request-changes 切替指示が prompt に不足"
fi

if grep -F 'unresolved == 0' "$WORKFLOW" > /dev/null && \
   grep -F 'unresolved >= 1' "$WORKFLOW" > /dev/null; then
  pass "sticky review の判定条件（unresolved 0 → approve / >= 1 → request-changes）が prompt に明示"
else
  fail "sticky review の判定条件が prompt に不足"
fi

echo "=== コード生成禁止（5 大方針 2） ==="

if grep -F 'コード生成は絶対' "$WORKFLOW" > /dev/null || \
   grep -F 'コード生成（docstring 全文 / unit-test' "$WORKFLOW" > /dev/null; then
  pass "5 大方針 2「コード生成禁止」が prompt に明示"
else
  fail "5 大方針 2「コード生成禁止」が prompt に不足"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
