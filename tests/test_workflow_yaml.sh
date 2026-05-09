#!/usr/bin/env bash
# vibehawk-review.yml workflow の最小要件検証
# Issue #59 経路 2 必須化: App Installation Token 認証、
# 3 secrets（VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY / CLAUDE_CODE_OAUTH_TOKEN）必須、
# actions/create-github-app-token@v2 で `vibehawk-for-<owner>[bot]` 名義投稿を実現
# Issue #22 妥協（GITHUB_TOKEN 1 系統）は #61 で撤回済み

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

echo "=== vibehawk-review.yml workflow 検証 ==="

# ファイル存在（前提: 不在なら全後続テスト無意味）
if [[ -f "$WORKFLOW" ]]; then
  pass "vibehawk-review.yml が存在する"
else
  fail "vibehawk-review.yml が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# コメント行を除外したワークフロー本文（行頭 # を除外）
WORKFLOW_BODY="$(awk '!/^[[:space:]]*#/' "$WORKFLOW")"

# pull_request トリガー
if echo "$WORKFLOW_BODY" | grep -E "^[[:space:]]*pull_request:" > /dev/null; then
  pass "pull_request トリガーが設定されている"
else
  fail "pull_request トリガーが設定されていない"
fi

# 必須イベントタイプ 3 種
for evt in opened synchronize ready_for_review; do
  if echo "$WORKFLOW_BODY" | grep -F "$evt" > /dev/null; then
    pass "イベントタイプ $evt が設定されている"
  else
    fail "イベントタイプ $evt が設定されていない"
  fi
done

# concurrency
if echo "$WORKFLOW_BODY" | grep -E "^concurrency:" > /dev/null; then
  pass "concurrency が設定されている"
else
  fail "concurrency が設定されていない"
fi

# cancel-in-progress: true（表記揺れ対応）
if echo "$WORKFLOW_BODY" | grep -E "cancel-in-progress:[[:space:]]*true" > /dev/null; then
  pass "cancel-in-progress: true が設定されている"
else
  fail "cancel-in-progress が true でない"
fi

# 最小権限（id-token: write は #22 で削除済み）
declare -a required_perms=(
  "pull-requests:[[:space:]]*write"
  "issues:[[:space:]]*write"
  "contents:[[:space:]]*read"
)
declare -a perm_labels=(
  "pull-requests: write"
  "issues: write"
  "contents: read"
)
for i in "${!required_perms[@]}"; do
  pattern="${required_perms[$i]}"
  label="${perm_labels[$i]}"
  if echo "$WORKFLOW_BODY" | grep -E "$pattern" > /dev/null; then
    pass "permissions: $label が設定されている"
  else
    fail "permissions: $label が設定されていない"
  fi
done

# 禁止権限不在（#22 修正で id-token: write も禁止対象に追加）
declare -a forbidden_perms=(
  "administration:[[:space:]]*write"
  "secrets:[[:space:]]*write"
  "workflows:[[:space:]]*write"
  "id-token:[[:space:]]*write"
)
declare -a forbidden_labels=(
  "administration: write"
  "secrets: write"
  "workflows: write"
  "id-token: write"
)
for i in "${!forbidden_perms[@]}"; do
  pattern="${forbidden_perms[$i]}"
  label="${forbidden_labels[$i]}"
  if echo "$WORKFLOW_BODY" | grep -E "$pattern" > /dev/null; then
    fail "禁止権限 $label が設定されている"
  else
    pass "禁止権限 $label が設定されていない"
  fi
done

# 経路 2 必須化（#59 / #61）: 利用者が設定する 3 secrets（VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY / CLAUDE_CODE_OAUTH_TOKEN）が全て参照される
declare -a required_secrets=(
  "CLAUDE_CODE_OAUTH_TOKEN"
  "VIBEHAWK_APP_ID"
  "VIBEHAWK_PRIVATE_KEY"
)
for sec in "${required_secrets[@]}"; do
  if echo "$WORKFLOW_BODY" | grep -F "$sec" > /dev/null; then
    pass "$sec 参照がある（経路 2 必須化）"
  else
    fail "$sec 参照がない（経路 2 必須化、#59）"
  fi
done

# claude-code-action の使用
if echo "$WORKFLOW_BODY" | grep -F "anthropics/claude-code-action" > /dev/null; then
  pass "anthropics/claude-code-action が呼ばれる"
else
  fail "anthropics/claude-code-action が呼ばれていない"
fi

# 経路 2 必須化（#59）: actions/create-github-app-token で App Installation Token を取得する
if echo "$WORKFLOW_BODY" | grep -F "actions/create-github-app-token" > /dev/null; then
  pass "actions/create-github-app-token が呼ばれる（経路 2 App Installation Token 認証）"
else
  fail "actions/create-github-app-token が呼ばれていない（経路 2 必須化、#59）"
fi

# サードパーティ Action SHA pin（CISO Major 指摘）
if echo "$WORKFLOW_BODY" | grep -E "anthropics/claude-code-action@[a-f0-9]{40}" > /dev/null; then
  pass "anthropics/claude-code-action が SHA pin されている"
else
  fail "anthropics/claude-code-action が SHA pin されていない"
fi

# fetch-depth: 0
if echo "$WORKFLOW_BODY" | grep -E "fetch-depth:[[:space:]]*0" > /dev/null; then
  pass "fetch-depth: 0 が設定されている"
else
  fail "fetch-depth: 0 が設定されていない"
fi

# draft skip ロジック
if echo "$WORKFLOW_BODY" | grep -F "draft == false" > /dev/null; then
  pass "draft skip ロジックが設定されている"
else
  fail "draft skip ロジック (draft == false) が設定されていない"
fi

# claude_args（claude-code-action のツール明示）
if echo "$WORKFLOW_BODY" | grep -F "claude_args:" > /dev/null; then
  pass "claude_args が設定されている（claude-code-action のツール明示）"
else
  fail "claude_args が設定されていない（claude-code-action が automatic review mode で動作しない）"
fi

# claude が PR コメント投稿できる allowedTools
if echo "$WORKFLOW_BODY" | grep -F "Bash(gh pr comment:*)" > /dev/null; then
  pass "allowedTools に Bash(gh pr comment:*) が含まれる"
else
  fail "allowedTools に Bash(gh pr comment:*) が含まれない（claude-code-action がコメント投稿できない）"
fi

# 経路 2 必須化（#59）: claude-code-action の github_token に App Installation Token (steps.app-token.outputs.token) を渡している
if echo "$WORKFLOW_BODY" | grep -E "github_token:[[:space:]]*\\\$\\{\\{[[:space:]]*steps\\.app-token\\.outputs\\.token[[:space:]]*\\}\\}" > /dev/null; then
  pass "github_token に App Installation Token (steps.app-token.outputs.token) が渡されている（経路 2）"
else
  fail "github_token に App Installation Token が渡されていない（経路 2 必須化、#59）"
fi

# 経路 2 必須化（#59）: app-token ステップが actions/create-github-app-token@v2 を使う
if echo "$WORKFLOW_BODY" | grep -E "actions/create-github-app-token@v2" > /dev/null; then
  pass "actions/create-github-app-token@v2 を使用している"
else
  fail "actions/create-github-app-token@v2 が使われていない（経路 2 必須化、#59）"
fi

# 経路 2 必須化（#59）: app-token ステップが secrets.VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY を参照する
if echo "$WORKFLOW_BODY" | grep -E "app-id:[[:space:]]*\\\$\\{\\{[[:space:]]*secrets\\.VIBEHAWK_APP_ID[[:space:]]*\\}\\}" > /dev/null; then
  pass "app-token ステップが app-id: secrets.VIBEHAWK_APP_ID を参照している"
else
  fail "app-token ステップが app-id: secrets.VIBEHAWK_APP_ID を参照していない（経路 2 必須化、#59）"
fi

if echo "$WORKFLOW_BODY" | grep -E "private-key:[[:space:]]*\\\$\\{\\{[[:space:]]*secrets\\.VIBEHAWK_PRIVATE_KEY[[:space:]]*\\}\\}" > /dev/null; then
  pass "app-token ステップが private-key: secrets.VIBEHAWK_PRIVATE_KEY を参照している"
else
  fail "app-token ステップが private-key: secrets.VIBEHAWK_PRIVATE_KEY を参照していない（経路 2 必須化、#59）"
fi

# 経路 2 必須化（#59）: claude-code-action の claude_code_oauth_token に secrets.CLAUDE_CODE_OAUTH_TOKEN を渡している
# （required_secrets ループの substring 検索は false positive 可能なため、明示的な参照形式を別途検証）
if echo "$WORKFLOW_BODY" | grep -E "claude_code_oauth_token:[[:space:]]*\\\$\\{\\{[[:space:]]*secrets\\.CLAUDE_CODE_OAUTH_TOKEN[[:space:]]*\\}\\}" > /dev/null; then
  pass "claude_code_oauth_token に secrets.CLAUDE_CODE_OAUTH_TOKEN が渡されている"
else
  fail "claude_code_oauth_token に secrets.CLAUDE_CODE_OAUTH_TOKEN が渡されていない（経路 2 必須化、#59）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
