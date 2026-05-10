#!/usr/bin/env bash
# Issue #11: vibehawk-chat.yml テンプレートの起動条件と無限ループ防止ロジックの検証
#
# 検証対象: `templates/.github/workflows/vibehawk-chat.yml`（npm 配布される
# テンプレート本体）。`.github/workflows/vibehawk-chat.yml`（dogfooding 用デプロイコピー）
# は test_workflow_template_snapshot.sh で templates と完全一致が検証される。
# Issue #56 dogfooding teardown で `.github/` 配下が一時削除されても、本テストは
# templates を見るため影響を受けない。

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

CHAT_WORKFLOW="${REPO_ROOT}/templates/.github/workflows/vibehawk-chat.yml"

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
# CodeRabbit PR #87 第 5 ラウンド Major 指摘: permissions block 内の key:value 完全一致検証
# 旧: ファイル全体 grep で permissions block 外の文字列に誤マッチする可能性
# 新: permissions ブロックを抽出して key:value 完全一致比較に統一
permission_kv="$(awk '
  /^[[:space:]]*permissions:/ { in_perm=1; next }
  in_perm && /^[^[:space:]]/ { in_perm=0 }
  in_perm && /^[[:space:]]+[a-z-]+:[[:space:]]*[a-z]+/ {
    sub(/^[[:space:]]+/, "")
    sub(/[[:space:]]+$/, "")
    print
  }
' "$CHAT_WORKFLOW" | sort -u)"

expected_permission_kv="$(printf '%s\n' 'contents: read' 'issues: write' 'pull-requests: write' | sort -u)"

if [[ "$permission_kv" == "$expected_permission_kv" ]]; then
  pass "permissions は key:value 完全一致 (pull-requests:write / issues:write / contents:read)"
else
  fail "permissions の key:value が完全一致しない: 実際=[$(echo "$permission_kv" | tr '\n' '|')], 期待=[$(echo "$expected_permission_kv" | tr '\n' '|')]"
fi

# 必須 / 禁止の個別ラベル明示も保持（運用時の可読性のため）
declare -a required_perm_labels=(
  "pull-requests: write"
  "issues: write"
  "contents: read"
)
for label in "${required_perm_labels[@]}"; do
  if echo "$permission_kv" | grep -F "$label" > /dev/null; then
    pass "permissions に $label が含まれる（必須権限）"
  else
    fail "permissions に $label が不足"
  fi
done

declare -a forbidden_perm_labels=(
  "administration: write"
  "secrets: write"
  "workflows: write"
  "id-token: write"
)
for label in "${forbidden_perm_labels[@]}"; do
  if echo "$permission_kv" | grep -F "$label" > /dev/null; then
    fail "permissions に禁止権限 $label が含まれる"
  else
    pass "permissions に禁止権限 $label が含まれない"
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

# CodeRabbit PR #87 第 4+5 ラウンド指摘: ready=true ガード step 単位走査（- 起点で未命名 step も検出）
# 旧: `- name:` 起点 → `- uses:` / `- run:` の未命名 step を見逃す
# 新: `id: check_secrets` を起点に、step 境界を `^[[:space:]]+- ` で判定
#     → 未命名 step も含めて全 step を走査、ready ガード未保有を検出
unguarded_steps=()
state="before"
current_step_marker=""  # 識別子（name / id / uses 値）
current_step_has_ready_guard=0
current_step_is_placeholder=0
current_step_is_check_secrets=0

flush_step() {
  # check_secrets 後 + 非例外（プレースホルダではない）+ ガードなし → 記録
  if [[ "$state" == "after_check_secrets" ]] && \
     [[ "$current_step_is_placeholder" == "0" ]] && \
     [[ "$current_step_has_ready_guard" == "0" ]] && \
     [[ "$current_step_is_check_secrets" == "0" ]] && \
     [[ -n "$current_step_marker" ]]; then
    unguarded_steps+=("$current_step_marker")
  fi
}

while IFS= read -r line; do
  # step 境界: 6 スペース indent + dash + space（jobs.<job>.steps[].* 直下）
  # markdown bullet（prompt 内の `- 項目`）は 12+ スペース indent なので誤マッチしない
  if [[ "$line" =~ ^[[:space:]]{6}-[[:space:]] ]] && [[ ! "$line" =~ ^[[:space:]]{7,} ]]; then
    flush_step
    current_step_marker="$(echo "$line" | sed -E 's/^[[:space:]]+-[[:space:]]+//; s/[[:space:]]+$//' | head -c 80)"
    current_step_has_ready_guard=0
    current_step_is_placeholder=0
    current_step_is_check_secrets=0
    # check_secrets ステップ自身は対象外（ガードしない、anchor）
    # 当ステップを表すマーカーを以後の line で id: check_secrets で確定する
    continue
  fi
  # id: check_secrets 検出 → このステップが check_secrets 自身
  if [[ "$line" =~ id:[[:space:]]+check_secrets ]]; then
    current_step_is_check_secrets=1
    state="check_secrets"
    continue
  fi
  # check_secrets 完了後の次の `^- ` 行で state を after_check_secrets に推移
  if [[ "$state" == "check_secrets" ]] && [[ "$current_step_is_check_secrets" == "0" ]]; then
    state="after_check_secrets"
  fi
  # ガード検出
  if [[ "$line" == *"if: steps.check_secrets.outputs.ready == 'true'"* ]]; then
    current_step_has_ready_guard=1
  fi
  # プレースホルダ投稿ステップは ready != 'true' で実行される設計
  if [[ "$line" == *"if: steps.check_secrets.outputs.ready != 'true'"* ]]; then
    current_step_is_placeholder=1
  fi
done < "$CHAT_WORKFLOW"

# 最後のステップ
flush_step

if [[ ${#unguarded_steps[@]} -eq 0 ]]; then
  pass "check_secrets 後の全 step (name / uses / run どれでも) が ready=true ガードまたは ready!='true' プレースホルダ例外を持つ"
else
  fail "check_secrets 後に ready ガードもプレースホルダ例外もない step: ${unguarded_steps[*]}"
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

# allowedTools（CodeRabbit PR #87 指摘: gh pr diff の取りこぼしを防ぐため明示的に列挙）
# CodeRabbit PR #106 Major 指摘: gh api / jq は issue_comment 経路でのプロンプト注入リスクのため除外
declare -a required_tools=(
  'cat:\*'
  'gh issue comment:\*'
  'gh pr comment:\*'
  'gh pr diff:\*'
)
for tool in "${required_tools[@]}"; do
  if grep -E "Bash\(${tool}\)" "$CHAT_WORKFLOW" > /dev/null; then
    pass "allowedTools に Bash(${tool}) が含まれる"
  else
    fail "allowedTools に Bash(${tool}) が含まれない"
  fi
done

# CodeRabbit PR #106 Major 指摘: gh api / jq が allowedTools に含まれないこと（外部入力プロンプト注入対策）
declare -a forbidden_tools=(
  'gh api:\*'
  'jq:\*'
)
for tool in "${forbidden_tools[@]}"; do
  if grep -E "Bash\(${tool}\)" "$CHAT_WORKFLOW" > /dev/null; then
    fail "allowedTools に Bash(${tool}) が含まれる（CodeRabbit PR #106 Major 指摘違反: issue_comment は外部入力でプロンプト注入で API 操作される）"
  else
    pass "allowedTools に Bash(${tool}) が含まれない（CodeRabbit PR #106 Major 指摘の最小権限化）"
  fi
done

# CodeRabbit PR #87 第 3+4 ラウンド Major 指摘: allowedTools whitelist 完全一致検証
# 第 3 ラウンドの head -1 限定では複数行 allowedTools を回避可能だったため、
# claude_args 全体（複数行 YAML literal block scalar）から Bash(...) パターンを全部抽出
# claude_args ブロック検出: claude_args: の次の `|` 行から、インデントが下がるまで
# シンプルに全ファイルから Bash(...) を抽出（workflow 内に Bash(...) は claude_args 内のみのはず）
# CodeRabbit PR #106 Major 指摘で gh api / jq を除外したため expected_set も縮小
unexpected_tools=()
expected_set='|cat:*|gh issue comment:*|gh pr comment:*|gh pr diff:*|'
while IFS= read -r tool; do
  # tool は "cat:*" のような Bash(...) 内の中身
  if [[ -n "$tool" ]] && [[ "$expected_set" != *"|${tool}|"* ]]; then
    unexpected_tools+=("$tool")
  fi
done < <(grep -oE 'Bash\([^)]+\)' "$CHAT_WORKFLOW" | sed -E 's/^Bash\(//; s/\)$//')

if [[ ${#unexpected_tools[@]} -eq 0 ]]; then
  pass "allowedTools は許可 4 項目のみで構成（claude_args 全体走査、Bash(*) 等の危険な追加なし、CodeRabbit PR #106 Major 反映）"
else
  fail "allowedTools に許可外の項目: ${unexpected_tools[*]}"
fi

# CodeRabbit PR #87 第 5 ラウンド Major 指摘: locale 解決ルール検証
# 仕様: .vibehawk.yaml 優先 → .coderabbit.yaml fallback → 未設定時 'en'
# vibehawk_config ステップに 3 経路すべての分岐ロジックが存在することを確認

# vibehawk_config ステップが存在
if grep -F 'id: vibehawk_config' "$CHAT_WORKFLOW" > /dev/null; then
  pass "vibehawk_config ステップが存在する（locale 解決のため）"
else
  fail "vibehawk_config ステップが不在（locale 解決が機能しない）"
fi

# .vibehawk.yaml 優先のチェック（先に file -f .vibehawk.yaml を見る）
if grep -F '.vibehawk.yaml' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F '.coderabbit.yaml' "$CHAT_WORKFLOW" > /dev/null; then
  # 優先順序: .vibehawk.yaml が elif より先にあること
  vibehawk_line="$(grep -nF '.vibehawk.yaml' "$CHAT_WORKFLOW" | head -1 | cut -d: -f1)"
  coderabbit_line="$(grep -nF '.coderabbit.yaml' "$CHAT_WORKFLOW" | head -1 | cut -d: -f1)"
  if [[ -n "$vibehawk_line" ]] && [[ -n "$coderabbit_line" ]] && [[ "$vibehawk_line" -lt "$coderabbit_line" ]]; then
    pass "locale 解決優先順序: .vibehawk.yaml が .coderabbit.yaml より先に評価される"
  else
    fail "locale 解決優先順序が不正: .vibehawk.yaml(L${vibehawk_line:-?}) vs .coderabbit.yaml(L${coderabbit_line:-?})"
  fi
else
  fail ".vibehawk.yaml / .coderabbit.yaml の両方が参照されていない"
fi

# 未設定時のデフォルト 'en' フォールバック
if grep -F 'language="en"' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F '// "en"' "$CHAT_WORKFLOW" > /dev/null; then
  pass "locale 未設定時 / null 時に 'en' フォールバック（jq // \"en\" + 初期値 language=\"en\"）"
else
  fail "locale 未設定時の 'en' フォールバックが不足"
fi

# language キーを GITHUB_OUTPUT に出力
if grep -E 'echo[[:space:]]+"language=' "$CHAT_WORKFLOW" > /dev/null; then
  pass "locale 解決結果が GITHUB_OUTPUT に language= で出力される"
else
  fail "locale 解決結果が GITHUB_OUTPUT に渡されていない"
fi

# claude-code-action prompt に LANGUAGE が渡される
if grep -F 'LANGUAGE: ${{ steps.vibehawk_config.outputs.language }}' "$CHAT_WORKFLOW" > /dev/null; then
  pass "claude-code-action prompt に LANGUAGE が渡される"
else
  fail "claude-code-action prompt に LANGUAGE が渡されていない"
fi

# prompt に LANGUAGE=ja → 日本語応答 / 他 → 英語応答 の指示
if grep -F 'LANGUAGE=ja' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F '日本語' "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に LANGUAGE=ja → 日本語応答 / それ以外 → 英語応答の指示が含まれる"
else
  fail "prompt の locale 別応答指示が不足"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
