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

if grep -F "!startsWith(github.event.comment.user.login, 'vibehawk-for-')" "$CHAT_WORKFLOW" > /dev/null; then
  pass "起動条件で否定 (!startsWith) により vibehawk-for-* Bot 自身を除外（無限ループ防止）"
else
  fail "起動条件で !startsWith による否定が不在（CodeRabbit PR #87 指摘: 否定なしだと Bot 許可状態で通過し得る）"
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

# 欠落時のハンドリング（CodeRabbit PR #87 Major 指摘）
# 「参照有無」だけでなく「missing 集計 → ready=false → プレースホルダコメント投稿 → app-token / thread_history スキップ」の全段ロジックを担保
if grep -F 'missing="$missing' "$CHAT_WORKFLOW" > /dev/null; then
  pass "secrets 欠落時の missing 集計ロジックが存在する"
else
  fail "secrets 欠落時の missing 集計ロジックが不足"
fi

if grep -F 'ready=false' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F 'ready=true' "$CHAT_WORKFLOW" > /dev/null; then
  pass "secrets 検証で ready=true / false の両分岐が存在する"
else
  fail "secrets 検証で ready=true / false の両分岐が不足"
fi

# プレースホルダコメント投稿ステップ: 未設定時のみ実行
if grep -F "if: steps.check_secrets.outputs.ready != 'true'" "$CHAT_WORKFLOW" > /dev/null && \
   grep -F 'gh issue comment' "$CHAT_WORKFLOW" | grep -F 'のため応答をスキップ' > /dev/null; then
  pass "secrets 欠落時のプレースホルダコメント投稿ステップが存在し、未設定時のみ実行される"
else
  fail "secrets 欠落時のプレースホルダコメント投稿ステップが不足（運用時の失敗動作見逃しリスク）"
fi

# 後続ステップ（app-token / thread_history / claude-code-action）が ready=true 時のみ実行
ready_true_count="$(grep -c "if: steps.check_secrets.outputs.ready == 'true'" "$CHAT_WORKFLOW" || true)"
if [[ "$ready_true_count" -ge 4 ]]; then
  pass "後続ステップが ready=true 条件でガードされている（${ready_true_count} 件）"
else
  fail "後続ステップの ready=true ガードが不足（${ready_true_count} 件、最低 4 件必要: app-token / thread_history / vibehawk_config / claude-code-action）"
fi

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

# CodeRabbit PR #87 Major 指摘: ページ結合の具体パターンを検証
# 各要素射影 + jq -s '.' slurp で N ページ任意対応を保証
if grep -F ".[] | {user: .user.login, created_at, body}" "$CHAT_WORKFLOW" > /dev/null; then
  pass "--jq で各要素射影 (.[] | {user, created_at, body}) が実装されている"
else
  fail "--jq の各要素射影パターンが不在（CodeRabbit PR #87 指摘: ページ結合に必須）"
fi

if grep -F "jq -s '.'" "$CHAT_WORKFLOW" > /dev/null; then
  pass "jq -s '.' でページ結合（slurp）が実装されている"
else
  fail "jq -s '.' でのページ結合が不在（CodeRabbit PR #87 指摘: 旧 .[0]+.[1]+flatten は 2 ページ前提）"
fi

# Issue 本文も含める（最初のコメントとして）
if grep -F 'issue_body' "$CHAT_WORKFLOW" > /dev/null; then
  pass "Issue 本文をスレッド履歴に含めるロジックが存在する"
else
  fail "Issue 本文の取り込みが実装されていない（最初のコメントが欠落する可能性）"
fi

# CodeRabbit PR #87 Major 指摘: Issue 本文を先頭に prepend する具体パターンを検証
if grep -F '[$issue] + .' "$CHAT_WORKFLOW" > /dev/null; then
  pass "Issue 本文を先頭に prepend する jq パターン ([\$issue] + .) が実装されている"
else
  fail "Issue 本文の先頭 prepend パターンが不在（時系列順序が崩れる可能性）"
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
