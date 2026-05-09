#!/usr/bin/env bash
# Issue #11: vibehawk-chat.yml の起動条件と無限ループ防止ロジックの検証

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

CHAT_WORKFLOW="${REPO_ROOT}/.github/workflows/vibehawk-chat.yml"

echo "=== vibehawk-chat.yml 構造検証（Issue #11） ==="

if [[ -f "$CHAT_WORKFLOW" ]]; then
  pass "vibehawk-chat.yml が存在する"
else
  fail "vibehawk-chat.yml が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# トリガー: issue_comment created のみ
if grep -E "^[[:space:]]*issue_comment:" "$CHAT_WORKFLOW" > /dev/null; then
  pass "issue_comment トリガーが設定されている"
else
  fail "issue_comment トリガーが設定されていない"
fi

if grep -E "types:[[:space:]]*\[created\]" "$CHAT_WORKFLOW" > /dev/null; then
  pass "issue_comment.types: [created] が設定されている（edit / delete に反応しない）"
else
  fail "issue_comment.types: [created] が設定されていない"
fi

# concurrency: cancel-in-progress: false（チャットは順次処理）
if grep -F "cancel-in-progress: false" "$CHAT_WORKFLOW" > /dev/null; then
  pass "concurrency: cancel-in-progress: false（チャットは順次処理、レビューと違って割り込み禁止）"
else
  fail "cancel-in-progress: false が設定されていない（チャット応答が中断される可能性）"
fi

# 起動条件: @vibehawk メンション + Bot 自身でない（無限ループ防止）
if grep -F "contains(github.event.comment.body, '@vibehawk')" "$CHAT_WORKFLOW" > /dev/null; then
  pass "起動条件に @vibehawk メンション検出が含まれる"
else
  fail "起動条件に @vibehawk メンション検出が含まれない"
fi

if grep -F "startsWith(github.event.comment.user.login, 'vibehawk-for-')" "$CHAT_WORKFLOW" > /dev/null; then
  pass "起動条件で vibehawk-for-* Bot 自身のメンションを除外（無限ループ防止）"
else
  fail "起動条件で vibehawk-for-* Bot 自身を除外していない（無限ループの危険）"
fi

# permissions: 最小権限（pull-requests:write / issues:write / contents:read）
declare -a required_perms=(
  "pull-requests:[[:space:]]*write"
  "issues:[[:space:]]*write"
  "contents:[[:space:]]*read"
)
for perm in "${required_perms[@]}"; do
  if grep -E "$perm" "$CHAT_WORKFLOW" > /dev/null; then
    pass "permissions: $perm が設定されている"
  else
    fail "permissions: $perm が設定されていない"
  fi
done

# 禁止権限不在
declare -a forbidden_perms=(
  "administration:[[:space:]]*write"
  "secrets:[[:space:]]*write"
  "workflows:[[:space:]]*write"
  "id-token:[[:space:]]*write"
)
for perm in "${forbidden_perms[@]}"; do
  if grep -E "$perm" "$CHAT_WORKFLOW" > /dev/null; then
    fail "禁止権限 $perm が含まれる"
  else
    pass "禁止権限 $perm が含まれない"
  fi
done

# 3 secrets 検証ステップ
for sec in VIBEHAWK_APP_ID VIBEHAWK_PRIVATE_KEY CLAUDE_CODE_OAUTH_TOKEN; do
  if grep -F "$sec" "$CHAT_WORKFLOW" > /dev/null; then
    pass "$sec が参照されている"
  else
    fail "$sec が参照されていない"
  fi
done

# App Installation Token を Use（review.yml と同じ仕組み）
if grep -F "actions/create-github-app-token@v2" "$CHAT_WORKFLOW" > /dev/null; then
  pass "actions/create-github-app-token@v2 を使用している"
else
  fail "actions/create-github-app-token@v2 を使用していない（経路 2 必須化、#59）"
fi

if grep -E "github_token:[[:space:]]*\\\$\\{\\{[[:space:]]*steps\\.app-token\\.outputs\\.token[[:space:]]*\\}\\}" "$CHAT_WORKFLOW" > /dev/null; then
  pass "claude-code-action に App Installation Token が渡されている"
else
  fail "claude-code-action に App Installation Token が渡されていない"
fi

# claude-code-action が SHA pin
if grep -E "anthropics/claude-code-action@[a-f0-9]{40}" "$CHAT_WORKFLOW" > /dev/null; then
  pass "anthropics/claude-code-action が SHA pin されている（CISO Major 条件）"
else
  fail "anthropics/claude-code-action が SHA pin されていない"
fi

# スレッド履歴取得ステップ
if grep -F "thread_history" "$CHAT_WORKFLOW" > /dev/null; then
  pass "thread_history ステップが存在する"
else
  fail "thread_history ステップが存在しない"
fi

if grep -F 'gh api "repos/${REPO}/issues/${ISSUE_NUMBER}/comments" --paginate' "$CHAT_WORKFLOW" > /dev/null; then
  pass "スレッド全コメント取得 (gh api ... --paginate) が実装されている"
else
  fail "スレッド全コメント取得が実装されていない"
fi

# Issue 本文も含める（最初のコメントとして）
if grep -F 'issue_body' "$CHAT_WORKFLOW" > /dev/null; then
  pass "Issue 本文をスレッド履歴に含めるロジックが存在する"
else
  fail "Issue 本文の取り込みが実装されていない（最初のコメントが欠落する可能性）"
fi

# prompt に無限ループ防止指示
if grep -F '応答本文に' "$CHAT_WORKFLOW" | grep -F '@vibehawk' > /dev/null && \
   grep -F '含めない' "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に「応答本文に @vibehawk を含めない」無限ループ防止指示が含まれる"
else
  fail "prompt に無限ループ防止指示が不足"
fi

# 5 大方針との整合（コード生成禁止 / 状態 GitHub 閉じる / メタデータ操作なし）
# bash の set -u + 多バイト文字で loop 変数が壊れる現象を回避するため、明示的に列挙する
if grep -F "5 大方針 2" "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に 5 大方針 2 (コード生成禁止) の言及がある"
else
  fail "prompt に 5 大方針 2 の整合言及がない"
fi

if grep -F "5 大方針 4" "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に 5 大方針 4 (専用 DB なし) の言及がある"
else
  fail "prompt に 5 大方針 4 の整合言及がない"
fi

if grep -F "5 大方針 5" "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に 5 大方針 5 (PR メタデータ操作なし) の言及がある"
else
  fail "prompt に 5 大方針 5 の整合言及がない"
fi

# 投稿コマンド（gh issue comment / gh pr comment）
if grep -F 'gh issue comment' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F 'gh pr comment' "$CHAT_WORKFLOW" > /dev/null; then
  pass "投稿コマンド（gh issue comment / gh pr comment 両方）が prompt に含まれる"
else
  fail "投稿コマンドが不足（PR / Issue 双方対応に必要）"
fi

# allowedTools（CodeRabbit PR #87 指摘: gh pr diff / jq の取りこぼしを防ぐため明示的に列挙）
declare -a required_tools=(
  'cat:\*'
  'gh issue comment:\*'
  'gh pr comment:\*'
  'gh pr diff:\*'
  'gh api:\*'
  'jq:\*'
)
for tool in "${required_tools[@]}"; do
  if grep -E "Bash\(${tool}\)" "$CHAT_WORKFLOW" > /dev/null; then
    pass "allowedTools に Bash(${tool}) が含まれる"
  else
    fail "allowedTools に Bash(${tool}) が含まれない"
  fi
done

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
