#!/usr/bin/env bash
# Issue #9: vibehawk-review.yml テンプレートの prompt に含まれる severity 5 段階分類規則の検証
#
# 検証対象: `templates/.github/workflows/vibehawk-review.yml`（npm 配布される
# テンプレート本体）。`.github/workflows/vibehawk-review.yml`（dogfooding 用デプロイコピー）
# は test_workflow_template_snapshot.sh で templates と完全一致が検証される。
# Issue #56 dogfooding teardown で `.github/` 配下が一時削除されても、本テストは
# templates を見るため影響を受けない。
#
# 検証項目:
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

WORKFLOW="${REPO_ROOT}/templates/.github/workflows/vibehawk-review.yml"

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

echo "=== inline comment 投稿指示（Issue #9 / Issue #121 bundled review API） ==="

# Issue #121: inline comments は bundled review POST の comments[] 配列で渡される
# （個別 POST `gh api -X POST .../pulls/.../comments` は撤廃、muted badge の原因）
if grep -F 'gh api -X POST' "$WORKFLOW" | grep -F 'pulls/$PR_NUMBER/reviews' > /dev/null; then
  pass "bundled review POST 経由の inline 投稿指示（gh api -X POST .../pulls/.../reviews）が prompt に含まれる（Issue #121）"
else
  fail "bundled review POST 経由の inline 投稿指示が prompt に含まれない（Issue #121）"
fi

# Issue #121: comments[] 配列の必須フィールドが JSON 形式で明示されている
# bundled review では `-f commit_id=` のような bash 形式ではなく、JSON ペイロード内で `"path":` `"line":` `"side":` として記載される
if grep -F '"path":' "$WORKFLOW" > /dev/null && \
   grep -F '"line":' "$WORKFLOW" > /dev/null && \
   grep -F '"side":' "$WORKFLOW" > /dev/null && \
   grep -F 'commit_id' "$WORKFLOW" > /dev/null; then
  pass "inline comment 必須フィールド（path / line / side / commit_id）が bundled review JSON 形式で prompt に明示（Issue #121）"
else
  fail "inline comment 必須フィールド（path / line / side / commit_id）が bundled review JSON 形式で揃っていない（Issue #121）"
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

echo "=== sticky review state（Issue #9 / Issue #121 bundled review API） ==="

# Issue #121: sticky review state は bundled review API の event フィールドで表現
# （`gh pr review --approve|--request-changes` から `gh api -X POST .../reviews -f event=APPROVE|REQUEST_CHANGES` に移行）
if grep -F 'APPROVE' "$WORKFLOW" > /dev/null && \
   grep -F 'REQUEST_CHANGES' "$WORKFLOW" > /dev/null; then
  pass "sticky review の APPROVE / REQUEST_CHANGES 切替指示が prompt に含まれる（Issue #121 bundled）"
else
  fail "sticky review の APPROVE / REQUEST_CHANGES 切替指示が prompt に不足（Issue #121）"
fi

# Issue #121: 旧 `gh pr review --approve|--request-changes` 経路は撤廃されているべき
if grep -F 'gh pr review' "$WORKFLOW" | grep -F -- '--approve' > /dev/null || \
   grep -F 'gh pr review' "$WORKFLOW" | grep -F -- '--request-changes' > /dev/null; then
  fail "旧 sticky review 経路（gh pr review --approve|--request-changes）が残っている（Issue #121、bundled 化で撤廃すべき）"
else
  pass "旧 sticky review 経路（gh pr review --approve|--request-changes）が撤廃されている（Issue #121 bundled）"
fi

if grep -F 'unresolved == 0' "$WORKFLOW" > /dev/null && \
   grep -F 'unresolved >= 1' "$WORKFLOW" > /dev/null; then
  pass "sticky review の判定条件（unresolved 0 → APPROVE / >= 1 → REQUEST_CHANGES）が prompt に明示"
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
