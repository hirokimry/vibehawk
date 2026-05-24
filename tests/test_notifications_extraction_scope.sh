#!/usr/bin/env bash
# notifications-extract-all 切り出し候補スキャナテスト
#
# .github/workflows/**/*.yml と hooks/**/*.sh から
# .claude/rules/notification-prompt-extraction.md の切り出し対象パターンを検出する。
# 検出 0 件で pass、1 件以上で fail（/vibecorp:notifications-extract-all の再実行を促す）。
#
# Issue #200 で本リポジトリに対する一括棚卸しを実施し、検出 0 件であることを
# 確認した。新たな --body / heredoc / script: が yaml に直接 embed された場合に
# このテストが fail することで extraction skill の再実行を喚起する。
#
# 検出ロジック（notification-prompt-extraction.md と機械整合）:
#   - .github/workflows/**/*.yml: --body "..." / heredoc (<<EOF) / script: ブロック
#   - hooks/**/*.sh: 長文 echo / printf / heredoc
#   - Claude `prompt: |` ブロック内のドキュメント例示は除外（実行コードではない）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
CANDIDATES=0

pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  FAILED=$((FAILED + 1))
}

echo "=== /vibecorp:notifications-extract-all 切り出し候補スキャン ==="

# 1. .github/workflows/**/*.yml: --body "..." / heredoc / script: ブロック
# Claude `prompt: |` ブロック内は除外（実行コードではなくエージェントへの指示文）。
scan_workflows() {
  local target_dir="$1"
  [[ -d "$target_dir" ]] || return 0
  for f in "$target_dir"/*.yml; do
    [[ -f "$f" ]] || continue
    awk -v F="$f" '
      /^[[:space:]]*prompt:[[:space:]]*\|/ {
        in_prompt = 1
        pi = match($0, /[^ ]/)
        next
      }
      in_prompt && /^[[:space:]]*[a-z_-]+:[[:space:]]*[^|]/ {
        indent = match($0, /[^ ]/)
        if (indent <= pi) in_prompt = 0
      }
      !in_prompt && /--body[ =]"/ {
        print F":"NR": [--body] " $0
      }
      !in_prompt && /<<-?[[:space:]]*["'"'"']?[A-Z][A-Z_]*/ {
        print F":"NR": [heredoc] " $0
      }
      !in_prompt && /^[[:space:]]*script:[[:space:]]*\|/ {
        print F":"NR": [script:] " $0
      }
    ' "$f"
  done
}

WORKFLOW_HITS=""
WORKFLOW_HITS="$(scan_workflows ".github/workflows")"
TEMPLATE_HITS=""
TEMPLATE_HITS="$(scan_workflows "templates/.github/workflows")"

if [[ -z "$WORKFLOW_HITS" ]]; then
  pass ".github/workflows: 切り出し候補なし"
else
  fail ".github/workflows: 切り出し候補を検出"
  echo "$WORKFLOW_HITS" | sed 's/^/    /'
  CANDIDATES=$((CANDIDATES + $(echo "$WORKFLOW_HITS" | wc -l | tr -d ' ')))
fi

if [[ -z "$TEMPLATE_HITS" ]]; then
  pass "templates/.github/workflows: 切り出し候補なし"
else
  fail "templates/.github/workflows: 切り出し候補を検出"
  echo "$TEMPLATE_HITS" | sed 's/^/    /'
  CANDIDATES=$((CANDIDATES + $(echo "$TEMPLATE_HITS" | wc -l | tr -d ' ')))
fi

# 2. hooks/**/*.sh: 長文 echo / printf / heredoc（連続 3 行以上）
# notification-prompt-extraction.md の閾値は 3 行以上で切り出し対象。
HOOK_HITS=""
if [[ -d "hooks" ]]; then
  HOOK_HITS="$(grep -rEn -e 'echo[[:space:]]+"' -e 'printf[[:space:]]+"' -e '<<-?[[:space:]]*["'"'"']?[A-Z][A-Z_]*' hooks/ 2>/dev/null || true)"
fi

if [[ -z "$HOOK_HITS" ]]; then
  if [[ -d "hooks" ]]; then
    pass "hooks/: 切り出し候補なし"
  else
    pass "hooks/: ディレクトリ不在（対象外）"
  fi
else
  # 連続 3 行以上のものだけを fail にしたいが、簡易化のため候補として全件報告
  fail "hooks/: 切り出し候補を検出（閾値 3 行以上を手動確認）"
  echo "$HOOK_HITS" | sed 's/^/    /'
  CANDIDATES=$((CANDIDATES + $(echo "$HOOK_HITS" | wc -l | tr -d ' ')))
fi

echo ""
echo "=== 結果: $PASSED passed, $FAILED failed (候補 $CANDIDATES 件) ==="

if [[ $FAILED -gt 0 ]]; then
  echo ""
  echo "📍 切り出し候補が検出されました。/vibecorp:notifications-extract-all を実行して"
  echo "   個別 .md ファイルへの切り出しを検討してください。"
  echo "   基準: .claude/rules/notification-prompt-extraction.md"
  exit 1
fi

exit 0
