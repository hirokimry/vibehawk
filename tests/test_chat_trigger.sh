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

# CodeRabbit PR #87 Major 指摘: concurrency.group がスレッド単位（issue.number）であることを検証
if grep -F 'group: vibehawk-chat-${{ github.event.issue.number }}' "$CHAT_WORKFLOW" > /dev/null; then
  pass "concurrency.group がスレッド単位 (vibehawk-chat-\${{ github.event.issue.number }}) で固定されている"
else
  fail "concurrency.group がスレッド単位で固定されていない（同一 PR/Issue 連投時の競合防止が崩れる）"
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

# CodeRabbit PR #87 Major 指摘: permissions 完全一致 whitelist 検証
# 「禁止 + 必須」だけでは「他の *: write が追加された」を検出できないため、
# permissions ブロック内に許可された 3 キー以外が存在しないことを確認
permission_keys="$(awk '
  /^[[:space:]]*permissions:/ { in_perm=1; next }
  in_perm && /^[^[:space:]]/ { in_perm=0 }
  in_perm && /^[[:space:]]+[a-z-]+:/ {
    sub(/^[[:space:]]+/, "")
    sub(/:.*/, "")
    print
  }
' "$CHAT_WORKFLOW" | sort -u)"

expected_permissions="$(printf '%s\n' contents issues pull-requests | sort -u)"

if [[ "$permission_keys" == "$expected_permissions" ]]; then
  pass "permissions は許可 3 キー (pull-requests / issues / contents) のみで完全一致（whitelist）"
else
  fail "permissions に許可外キーが存在 / 必要キーが不足: 実際=[$(echo "$permission_keys" | tr '\n' ',')], 期待=[pull-requests,issues,contents]"
fi

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

# CodeRabbit PR #87 第 4 ラウンド指摘: 件数依存ではなく step 単位で完全走査
# check_secrets の後にある全 step の name を抽出し、プレースホルダ投稿（例外）以外は
# 全て `if: steps.check_secrets.outputs.ready == 'true'` ガードを持つことを保証する
unguarded_steps=()
state="before_check_secrets"
current_step=""
current_step_has_ready_guard=0
current_step_is_placeholder=0

while IFS= read -r line; do
  # ステップ name 行を検出（- name: で始まる）
  if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+name:[[:space:]] ]]; then
    # 前のステップの判定: check_secrets 後のステップで、プレースホルダ例外でなく、ready ガードがない場合は記録
    if [[ "$state" == "after_check_secrets" ]] && [[ "$current_step_is_placeholder" == "0" ]] && [[ "$current_step_has_ready_guard" == "0" ]] && [[ -n "$current_step" ]]; then
      unguarded_steps+=("$current_step")
    fi
    # 新しいステップ開始
    current_step="$(echo "$line" | sed -E 's/^[[:space:]]+-[[:space:]]+name:[[:space:]]+//; s/[[:space:]]+$//')"
    current_step_has_ready_guard=0
    current_step_is_placeholder=0
    if [[ "$current_step" == *"secrets 検証"* ]]; then
      state="check_secrets"
    elif [[ "$state" == "check_secrets" ]] || [[ "$state" == "after_check_secrets" ]]; then
      state="after_check_secrets"
    fi
    # プレースホルダ投稿ステップは例外（ready != 'true' で実行される設計）
    if [[ "$current_step" == *"プレースホルダ"* ]] || [[ "$current_step" == *"placeholder"* ]]; then
      current_step_is_placeholder=1
    fi
    continue
  fi
  # ガード行を検出
  if [[ "$line" == *"if: steps.check_secrets.outputs.ready == 'true'"* ]]; then
    current_step_has_ready_guard=1
  fi
done < "$CHAT_WORKFLOW"

# 最後のステップの判定
if [[ "$state" == "after_check_secrets" ]] && [[ "$current_step_is_placeholder" == "0" ]] && [[ "$current_step_has_ready_guard" == "0" ]] && [[ -n "$current_step" ]]; then
  unguarded_steps+=("$current_step")
fi

if [[ ${#unguarded_steps[@]} -eq 0 ]]; then
  pass "check_secrets 後の全 step が ready=true ガードを持つ（プレースホルダ投稿を除く、step 単位走査）"
else
  fail "check_secrets 後に ready=true ガードのない step: ${unguarded_steps[*]}"
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

# CodeRabbit PR #87 Major 指摘: TRIGGERING_USER 経由の二重ガードを検証
# トリガー条件 if で弾かれているが、prompt 側でも TRIGGERING_USER が vibehawk-for-* なら何もしない指示を担保
if grep -F 'TRIGGERING_USER' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F 'vibehawk-for-' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F '何もせず終了' "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に TRIGGERING_USER が vibehawk-for-* なら何もせず終了する二重ガード指示が含まれる"
else
  fail "prompt に TRIGGERING_USER 経由の二重ガード指示が不足（トリガー if のみだとガード退行リスク）"
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

# CodeRabbit PR #87 第 3+4 ラウンド Major 指摘: allowedTools whitelist 完全一致検証
# 第 3 ラウンドの head -1 限定では複数行 allowedTools を回避可能だったため、
# claude_args 全体（複数行 YAML literal block scalar）から Bash(...) パターンを全部抽出
# claude_args ブロック検出: claude_args: の次の `|` 行から、インデントが下がるまで
# シンプルに全ファイルから Bash(...) を抽出（workflow 内に Bash(...) は claude_args 内のみのはず）
unexpected_tools=()
expected_set='|cat:*|gh issue comment:*|gh pr comment:*|gh pr diff:*|gh api:*|jq:*|'
while IFS= read -r tool; do
  # tool は "cat:*" のような Bash(...) 内の中身
  if [[ -n "$tool" ]] && [[ "$expected_set" != *"|${tool}|"* ]]; then
    unexpected_tools+=("$tool")
  fi
done < <(grep -oE 'Bash\([^)]+\)' "$CHAT_WORKFLOW" | sed -E 's/^Bash\(//; s/\)$//')

if [[ ${#unexpected_tools[@]} -eq 0 ]]; then
  pass "allowedTools は許可 6 項目のみで構成（claude_args 全体走査、Bash(*) 等の危険な追加なし）"
else
  fail "allowedTools に許可外の項目: ${unexpected_tools[*]}"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
