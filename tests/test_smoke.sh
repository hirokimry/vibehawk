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

# MVV.md のプレースホルダ検証（空テンプレでないことを保証）
if [[ -f "MVV.md" ]]; then
  if grep -F "（ここに" MVV.md > /dev/null; then
    remaining=$(grep -nF "（ここに" MVV.md)
    fail "MVV.md にプレースホルダが残っている:"$'\n'"$remaining"
  else
    pass "MVV.md にプレースホルダが残っていない"
  fi
fi

# docs/specification.md に "vibehawk" が含まれる（Issue #5 反映確認）
if [[ -f "docs/specification.md" ]]; then
  if grep -F "vibehawk" docs/specification.md > /dev/null; then
    pass "docs/specification.md に vibehawk 反映"
  else
    fail "docs/specification.md に vibehawk が反映されていない"
  fi
else
  fail "docs/specification.md が存在しない"
fi

# docs/POLICY.md に「プロダクト方針（5 大方針）」見出しが含まれる
if [[ -f "docs/POLICY.md" ]]; then
  if grep -F "プロダクト方針（5 大方針）" docs/POLICY.md > /dev/null; then
    pass "docs/POLICY.md に 5 大方針反映"
  else
    fail "docs/POLICY.md に 5 大方針が反映されていない"
  fi
else
  fail "docs/POLICY.md が存在しない"
fi

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
