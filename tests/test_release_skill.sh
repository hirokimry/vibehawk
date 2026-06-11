#!/usr/bin/env bash
# /release skill（版上げ係、Issue #341）の静的検証
#
# SKILL.md は LLM 向け手順書のため実行テストは行わず、
# 中核セクション・規約準拠（frontmatter / fence 言語指定）の存在を grep で検証する。
# 将来の SKILL.md 改変で中断ガード等が脱落した場合にここで検知する。

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

SKILL="${REPO_ROOT}/.claude/skills/release/SKILL.md"

echo "=== /release skill 静的検証 ==="

if [[ -f "$SKILL" ]]; then
  pass "SKILL.md が存在する"
else
  fail "SKILL.md が存在しない"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了（testing.md）
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# --- frontmatter（prompt-writing.md 準拠） ---

if grep -q -e '^name: release$' "$SKILL"; then
  pass "frontmatter に name: release がある（ディレクトリ名と一致）"
else
  fail "frontmatter の name: release が無い"
fi

if grep -q -e '^description: ' "$SKILL"; then
  pass "frontmatter に description がある"
else
  fail "frontmatter の description が無い"
fi

if grep -q -e '「/release」' "$SKILL" && grep -q -e 'リリースして' "$SKILL"; then
  pass "description に呼び出しトリガー語句が含まれる"
else
  fail "description の呼び出しトリガー語句が不足している"
fi

# --- bump 実体への参照 ---

if grep -q -e 'scripts/ci/release/prepare-release\.sh' "$SKILL"; then
  pass "prepare-release.sh への参照がある（bump 実体への委譲）"
else
  fail "prepare-release.sh への参照が無い"
fi

# --- 中核セクション（介入ポイント含む）---

if grep -q -e '前提確認' "$SKILL"; then
  pass "前提確認ステップがある"
else
  fail "前提確認ステップが無い"
fi

if grep -q -e 'Unreleased ガード' "$SKILL"; then
  pass "Unreleased ガードがある（完了条件③の安全弁）"
else
  fail "Unreleased ガードが無い"
fi

if grep -q -e 'リリース対象の変更（feat / fix / perf / breaking）が無い' "$SKILL"; then
  pass "bump なし時の中断（リリース対象なし報告）がある"
else
  fail "bump なし時の中断記述が無い"
fi

if grep -q -e 'release/v' "$SKILL"; then
  pass "release/v ブランチ命名がある"
else
  fail "release/v ブランチ命名が無い"
fi

if grep -q -e 'Refs #N' "$SKILL"; then
  pass "Refs #N 列挙がある（pr-issue-link-check 対応）"
else
  fail "Refs #N 列挙が無い"
fi

if grep -q -e 'gh pr merge --squash --auto' "$SKILL"; then
  pass "auto-merge 設定がある"
else
  fail "auto-merge 設定が無い"
fi

if grep -q -e '🚀 release: vibehawk を v' "$SKILL"; then
  pass "release: タイトル prefix がある（check-pr-title.sh 許可済み形式）"
else
  fail "release: タイトル prefix が無い"
fi

if grep -q -e '/vibecorp:pr-fix-loop' "$SKILL" && grep -q -e 'fallback' "$SKILL"; then
  pass "/vibecorp:pr-fix-loop 前提と fallback がある"
else
  fail "/vibecorp:pr-fix-loop 前提または fallback が無い"
fi

# --- git 追跡対象であること（.claude/.gitignore の skills/* 一括 ignore に飲まれていないか）---

if git -C "$REPO_ROOT" check-ignore -q .claude/skills/release/SKILL.md; then
  fail "SKILL.md が gitignore されている（.claude/.gitignore の !skills/release/ 例外が消えた）"
else
  pass "SKILL.md は gitignore されていない（追跡可能）"
fi

# --- markdown.md: 言語指定なしフェンス禁止 ---
# 開始フェンスを奇数番目として数え、言語指定の無い開始フェンスを検出する。
unlabeled=$(awk '
  /^```/ {
    count++
    if (count % 2 == 1 && $0 == "```") unlabeled++
  }
  END { print unlabeled + 0 }
' "$SKILL")

if [[ "$unlabeled" -eq 0 ]]; then
  pass "言語指定なしの開始フェンスが無い（markdown.md 準拠）"
else
  fail "言語指定なしの開始フェンスが ${unlabeled} 件ある"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
