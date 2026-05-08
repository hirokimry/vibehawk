#!/usr/bin/env bash
# vibehawk リポジトリのスモークテスト
# vibecorp プラグイン導入後に必要なファイル・設定が揃っていることを検証する。

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

echo "=== vibehawk smoke test ==="

# 必須ファイルの存在確認
for f in README.md MVV.md .coderabbit.yaml .claude/vibecorp.yml; do
  if [[ -f "$f" ]]; then
    pass "$f が存在する"
  else
    fail "$f が存在しない"
  fi
done

# 後続テストは .claude/vibecorp.yml に依存するため、不在なら早期終了
if [[ ! -f ".claude/vibecorp.yml" ]]; then
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# preset: full
if awk '/^preset:[[:space:]]*full[[:space:]]*$/{found=1} END{exit !found}' .claude/vibecorp.yml; then
  pass "preset: full"
else
  fail "preset が full でない"
fi

# claude_action.enabled: false (YAML ブロック内のキーを awk で抽出)
if awk '
  /^claude_action:/ {in_section = 1; next}
  in_section && /^[a-z]/ {in_section = 0}
  in_section && /^[[:space:]]+enabled:[[:space:]]*false[[:space:]]*$/ {found = 1}
  END {exit !found}
' .claude/vibecorp.yml; then
  pass "claude_action.enabled: false (CodeRabbit 単独運用)"
else
  fail "claude_action.enabled が false でない"
fi

# claude-code-action 関連が削除されていること
for f in REVIEW.md .github/workflows/ai-review.yml; do
  if [[ ! -e "$f" ]]; then
    pass "$f が存在しない（CodeRabbit のみ運用）"
  else
    fail "$f が残っている"
  fi
done

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
