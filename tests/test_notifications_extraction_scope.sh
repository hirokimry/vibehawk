#!/usr/bin/env bash
# notifications-extract-all 切り出し候補スキャナテスト
#
# .github/workflows/**/*.{yml,yaml} と hooks/**/*.sh から
# .claude/rules/notification-prompt-extraction.md の切り出し対象パターンを検出する。
# 検出 0 件で pass、1 件以上で fail（/vibecorp:notifications-extract-all の再実行を促す）。
#
# Issue #200 で本リポジトリに対する一括棚卸しを実施し、検出 0 件であることを
# 確認した。新たな --body / heredoc / script: が yaml に直接 embed された場合、
# または hooks/ に 3 行以上の echo/printf/heredoc が追加された場合、
# このテストが fail することで extraction skill の再実行を喚起する。
#
# 検出ロジック（notification-prompt-extraction.md と機械整合）:
#   - .github/workflows/**/*.{yml,yaml}: --body "..." / heredoc (<<EOF) / script: ブロック
#     （再帰スキャン + yaml 拡張子両対応）
#   - hooks/**/*.sh: 3 行以上の長文 echo / printf / heredoc
#     （閾値: notification-prompt-extraction.md の「3 行以上」と整合）
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

# 前提: 基準ルールファイルが存在すること（不在なら本テストの目的が成立しない）
# 📍 根拠: testing.md「前提ファイル不在時は fail() の後に明示的に exit 1 する」
if [[ ! -f ".claude/rules/notification-prompt-extraction.md" ]]; then
  fail ".claude/rules/notification-prompt-extraction.md が見つかりません"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# 1. .github/workflows/**/*.{yml,yaml}: --body "..." / heredoc / script: ブロック
# Claude `prompt: |` ブロック内は除外（実行コードではなくエージェントへの指示文）。
# 再帰スキャンで yml / yaml 両方を拾う（notification-prompt-extraction.md paths と整合）。
scan_workflows() {
  local target_dir="$1"
  [[ -d "$target_dir" ]] || return 0
  while IFS= read -r -d '' f; do
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
  done < <(find "$target_dir" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)
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

# 2. hooks/**/*.sh: 3 行以上の長文 echo / printf / heredoc
# notification-prompt-extraction.md の閾値「3 行以上」を機械判定する:
#   - echo/printf "..." 内のリテラル \n 数 + 1 が 3 以上で長文と判定
#   - heredoc (<<EOF / <<-EOF) は構造的に複数行となるため常に検出対象
HOOK_HITS=""
if [[ -d "hooks" ]]; then
  HOOK_HITS="$(find hooks -type f -name '*.sh' -print0 | xargs -0 awk '
    {
      if ($0 ~ /(echo|printf)[[:space:]]+"/) {
        n = gsub(/\\n/, "&")
        if (n + 1 >= 3) print FILENAME ":" FNR ": [long-echo/printf] " $0
      }
      if ($0 ~ /<<-?[[:space:]]*["'"'"']?[A-Z][A-Z_]*/) {
        print FILENAME ":" FNR ": [heredoc] " $0
      }
    }
  ')"
fi

if [[ -z "$HOOK_HITS" ]]; then
  if [[ -d "hooks" ]]; then
    pass "hooks/: 切り出し候補なし（3 行以上の echo/printf/heredoc は検出なし）"
  else
    pass "hooks/: ディレクトリ不在（対象外）"
  fi
else
  fail "hooks/: 切り出し候補を検出（閾値 3 行以上の長文）"
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
