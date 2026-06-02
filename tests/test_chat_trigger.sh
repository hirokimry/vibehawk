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

# Issue #177: vibehawk-chat.yml の 7 ブロックの run: shell は scripts/ci/vibehawk-chat/*.sh
# に切り出されている。本テストは yaml の構造（env / if / id / action 参照 / prompt 内容 /
# allowedTools）と、切り出されたシェルロジック（missing 集計、thread 取得、bundled review
# POST、check-runs POST 等）の両方を検証する必要がある。
#
# `CHAT_SCRIPTS_DIR` 配下のシェルを連結した内容を `CHAT_SCRIPTS_CONTENT` に保持し、
# yaml 構造検証は引き続き `$CHAT_WORKFLOW` を直接 grep、シェルロジック検証は
# `$CHAT_WORKFLOW` と `$CHAT_SCRIPTS_CONTENT` を結合した `$CHAT_SURFACE` を grep する。
CHAT_SCRIPTS_DIR="${REPO_ROOT}/scripts/ci/vibehawk-chat"

echo "=== vibehawk-chat.yml 構造検証（Issue #11） ==="

if [[ -f "$CHAT_WORKFLOW" ]]; then
  pass "vibehawk-chat.yml が存在する"
else
  fail "vibehawk-chat.yml が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# Issue #177: 切り出し先ディレクトリと 7 本のシェルが揃っていることを検証
if [[ -d "$CHAT_SCRIPTS_DIR" ]]; then
  pass "scripts/ci/vibehawk-chat/ ディレクトリが存在する（Issue #177 切り出し先）"
else
  fail "scripts/ci/vibehawk-chat/ ディレクトリが存在しない（Issue #177 切り出し先）"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

declare -a expected_chat_scripts=(
  "check-secrets.sh"
  "post-placeholder.sh"
  "fetch-thread-history.sh"
  "load-config.sh"
  "fetch-pr-head.sh"
  "post-bundled-review.sh"
  "post-status-check.sh"
  "detect-review-diff.sh"
  "re-evaluate-verdict.sh"
  "post-recheck-notice.sh"
  "resolve-own-threads.sh"
)
for s in "${expected_chat_scripts[@]}"; do
  if [[ -f "${CHAT_SCRIPTS_DIR}/${s}" ]]; then
    pass "scripts/ci/vibehawk-chat/${s} が存在する（Issue #177）"
  else
    fail "scripts/ci/vibehawk-chat/${s} が存在しない（Issue #177）"
  fi
done

# 切り出した全シェルを連結（シェルロジック検証用）
CHAT_SCRIPTS_CONTENT="$(cat "${CHAT_SCRIPTS_DIR}"/*.sh 2>/dev/null || true)"

# yaml + scripts 全体の surface area（シェルロジック検証用）
CHAT_SURFACE="$(cat "$CHAT_WORKFLOW"; printf '\n'; printf '%s\n' "$CHAT_SCRIPTS_CONTENT")"

# Issue #177: yaml の run: ブロックがラッパー呼び出しのみであること（5 行以下、scripts/ci/
# vibehawk-chat/ への委譲）。`run:` 直値が `bash scripts/ci/vibehawk-chat/<name>.sh` 形式の
# 1 行になっていれば OK。
run_lines="$(grep -E '^[[:space:]]+run:[[:space:]]' "$CHAT_WORKFLOW" || true)"
run_total="$(printf '%s\n' "$run_lines" | grep -c -v '^$' || true)"
run_wrappers="$(printf '%s\n' "$run_lines" | grep -c 'bash scripts/ci/vibehawk-chat/' || true)"
if [[ "$run_total" -gt 0 ]] && [[ "$run_total" == "$run_wrappers" ]]; then
  pass "yaml の全 run: が scripts/ci/vibehawk-chat/ への 1 行ラッパー（Issue #177、${run_wrappers}/${run_total} 件）"
else
  fail "yaml に scripts/ci/vibehawk-chat/ 以外の run: が残っている（${run_wrappers}/${run_total} 件のみラッパー）"
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

# Issue #135: `@vibehawk review` 経路で後続 step が check-runs を post するため checks: write を追加
expected_permission_kv="$(printf '%s\n' 'contents: read' 'issues: write' 'pull-requests: write' 'checks: write' | sort -u)"

if [[ "$permission_kv" == "$expected_permission_kv" ]]; then
  pass "permissions は key:value 完全一致 (pull-requests:write / issues:write / contents:read / checks:write)"
else
  fail "permissions の key:value が完全一致しない: 実際=[$(echo "$permission_kv" | tr '\n' '|')], 期待=[$(echo "$expected_permission_kv" | tr '\n' '|')]"
fi

# 必須 / 禁止の個別ラベル明示も保持（運用時の可読性のため）
declare -a required_perm_labels=(
  "pull-requests: write"
  "issues: write"
  "contents: read"
  "checks: write"
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
# Issue #177: シェルロジックは scripts/ci/vibehawk-chat/check-secrets.sh / post-placeholder.sh に切り出し済み
if echo "$CHAT_SURFACE" | grep -F 'missing="$missing' > /dev/null; then
  pass "secrets 欠落時の missing 集計ロジックが存在する（scripts/ci/vibehawk-chat/check-secrets.sh）"
else
  fail "secrets 欠落時の missing 集計ロジックが不足"
fi

if echo "$CHAT_SURFACE" | grep -F 'ready=false' > /dev/null && \
   echo "$CHAT_SURFACE" | grep -F 'ready=true' > /dev/null; then
  pass "secrets 検証で ready=true / false の両分岐が存在する（scripts/ci/vibehawk-chat/check-secrets.sh）"
else
  fail "secrets 検証で ready=true / false の両分岐が不足"
fi

# プレースホルダコメント投稿ステップ: 未設定時のみ実行
# yaml 側で `if: ready != 'true'` ガード、シェル本体は scripts/ci/vibehawk-chat/post-placeholder.sh
if grep -F "if: steps.check_secrets.outputs.ready != 'true'" "$CHAT_WORKFLOW" > /dev/null && \
   echo "$CHAT_SURFACE" | grep -F 'gh issue comment' | grep -F 'のため応答をスキップ' > /dev/null; then
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
  # ガード検出（単一行 `if:` および block-folded `if: |` 内のいずれも検知）
  # Issue #135: `@vibehawk review` 経路の check-runs POST step は多条件 AND を
  # 多行 `if: |` で書くため、`if:` プレフィックスを必須としない形に緩める
  if [[ "$line" == *"steps.check_secrets.outputs.ready == 'true'"* ]]; then
    current_step_has_ready_guard=1
  fi
  # プレースホルダ投稿ステップは ready != 'true' で実行される設計
  if [[ "$line" == *"steps.check_secrets.outputs.ready != 'true'"* ]]; then
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

# Issue #177: スレッド全コメント取得ロジックは scripts/ci/vibehawk-chat/fetch-thread-history.sh に切り出し済み
if echo "$CHAT_SURFACE" | grep -F 'gh api "repos/${REPO}/issues/${ISSUE_NUMBER}/comments" --paginate' > /dev/null; then
  pass "スレッド全コメント取得 (gh api ... --paginate) が実装されている（scripts/ci/vibehawk-chat/fetch-thread-history.sh）"
else
  fail "スレッド全コメント取得が実装されていない"
fi

# CodeRabbit PR #87 Major 指摘: ページ結合の具体パターンを検証
# 各要素射影 + jq -s '.' slurp で N ページ任意対応を保証
if echo "$CHAT_SURFACE" | grep -F ".[] | {user: .user.login, created_at, body}" > /dev/null; then
  pass "--jq で各要素射影 (.[] | {user, created_at, body}) が実装されている"
else
  fail "--jq の各要素射影パターンが不在（CodeRabbit PR #87 指摘: ページ結合に必須）"
fi

if echo "$CHAT_SURFACE" | grep -F "jq -s '.'" > /dev/null; then
  pass "jq -s '.' でページ結合（slurp）が実装されている"
else
  fail "jq -s '.' でのページ結合が不在（CodeRabbit PR #87 指摘: 旧 .[0]+.[1]+flatten は 2 ページ前提）"
fi

# Issue 本文も含める（最初のコメントとして）
if echo "$CHAT_SURFACE" | grep -F 'issue_body' > /dev/null; then
  pass "Issue 本文をスレッド履歴に含めるロジックが存在する"
else
  fail "Issue 本文の取り込みが実装されていない（最初のコメントが欠落する可能性）"
fi

# CodeRabbit PR #87 Major 指摘: Issue 本文を先頭に prepend する具体パターンを検証
if echo "$CHAT_SURFACE" | grep -F '[$issue] + .' > /dev/null; then
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
# Issue #135 セキュリティ修正: `@vibehawk review` 経路でも Claude prompt 内では API を呼ばず、
#   payload をファイルに書いて後続 workflow step が決定論的に POST する設計に変更（Issue #121-C1
#   fix と同じ思想）。これにより allowedTools は PR #106 baseline 4 項目を維持し、`gh api:*` /
#   `jq:*` の禁止も継続できる。
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
# Issue #135 セキュリティ修正: `gh api -X POST repos/:*` は repos/ 以下の全 POST エンドポイント
#   （labels, merge, comments 等）を許す過広パターンであり、PR #106 のセキュリティ境界を後退
#   させるため不採用。bundled review POST は workflow step で決定論的に行う。
declare -a forbidden_tools=(
  'gh api:\*'
  'jq:\*'
  'gh api -X POST repos/:\*'
  'gh pr view:\*'
)
declare -a forbidden_tool_reasons=(
  '汎用 API 操作（CodeRabbit PR #106 Major: プロンプト注入リスク）'
  '汎用 JSON 操作（CodeRabbit PR #106 Major: プロンプト注入時の任意 API ペイロード組立を防止）'
  'repos/ 配下の全 POST エンドポイントを許す過広パターン（Issue #135 セキュリティ修正: prompt injection で labels/merge/comments 等の操作を許可してしまう）'
  '不要（HEAD SHA は workflow step pr_head が fetch して prompt に渡す、Issue #135 セキュリティ修正）'
)
for i in "${!forbidden_tools[@]}"; do
  tool="${forbidden_tools[$i]}"
  reason="${forbidden_tool_reasons[$i]}"
  if grep -E "Bash\(${tool}\)" "$CHAT_WORKFLOW" > /dev/null; then
    fail "allowedTools に Bash(${tool}) が含まれる（理由: ${reason}）"
  else
    pass "allowedTools に Bash(${tool}) が含まれない（理由: ${reason}）"
  fi
done

# CodeRabbit PR #87 第 3+4 ラウンド Major 指摘: allowedTools whitelist 完全一致検証
# Issue #135 セキュリティ修正で PR #106 baseline 4 項目に戻した（chat 経路では API 操作を一切
# 行わず、payload ファイル出力のみ → workflow step が決定論 POST）。
unexpected_tools=()
expected_set='|cat:*|gh issue comment:*|gh pr comment:*|gh pr diff:*|'
while IFS= read -r tool; do
  # tool は "cat:*" のような Bash(...) 内の中身
  if [[ -n "$tool" ]] && [[ "$expected_set" != *"|${tool}|"* ]]; then
    unexpected_tools+=("$tool")
  fi
done < <(grep -oE 'Bash\([^)]+\)' "$CHAT_WORKFLOW" | sed -E 's/^Bash\(//; s/\)$//')

if [[ ${#unexpected_tools[@]} -eq 0 ]]; then
  pass "allowedTools は許可 4 項目のみで構成（PR #106 baseline 維持、Issue #135 セキュリティ修正で gh api / gh pr view を撤去）"
else
  fail "allowedTools に許可外の項目: ${unexpected_tools[*]}"
fi

# Issue #172: locale 解決ルール検証
# 仕様: .vibehawk.yaml 単独 → 未設定時 'en'（CodeRabbit PR #87 で導入された .coderabbit.yaml fallback は #172 で撤廃）
# vibehawk_config ステップに 2 経路すべての分岐ロジックが存在することを確認

# vibehawk_config ステップが存在
if grep -F 'id: vibehawk_config' "$CHAT_WORKFLOW" > /dev/null; then
  pass "vibehawk_config ステップが存在する（locale 解決のため）"
else
  fail "vibehawk_config ステップが不在（locale 解決が機能しない）"
fi

# .vibehawk.yaml 単独受付の検証（Issue #172 で .coderabbit.yaml fallback 撤廃）
# Issue #177: シェル本体は scripts/ci/vibehawk-chat/load-config.sh に切り出し済み
if echo "$CHAT_SURFACE" | grep -F '.vibehawk.yaml' > /dev/null; then
  pass ".vibehawk.yaml が参照される（locale 解決の単独設定ソース、scripts/ci/vibehawk-chat/load-config.sh）"
else
  fail ".vibehawk.yaml の参照が不足（locale 解決が機能しない）"
fi

# .coderabbit.yaml の読込経路（ファイル存在 check / config_file 代入）が撤廃されている
if ! echo "$CHAT_SURFACE" | grep -F '[[ -f ".coderabbit.yaml" ]]' > /dev/null && \
   ! echo "$CHAT_SURFACE" | grep -F 'config_file=".coderabbit.yaml"' > /dev/null; then
  pass ".coderabbit.yaml の読込経路が存在しない（Issue #172 fallback 撤廃）"
else
  fail ".coderabbit.yaml の読込経路が残っている（Issue #172 で撤廃済のはず）"
fi

# 未設定時のデフォルト 'en' フォールバック
if echo "$CHAT_SURFACE" | grep -F 'language="en"' > /dev/null && \
   echo "$CHAT_SURFACE" | grep -F '// "en"' > /dev/null; then
  pass "locale 未設定時 / null 時に 'en' フォールバック（jq // \"en\" + 初期値 language=\"en\"）"
else
  fail "locale 未設定時の 'en' フォールバックが不足"
fi

# language キーを GITHUB_OUTPUT に出力
# Issue #177: 切り出し先 (load-config.sh) では echo "language=$language" >> "$GITHUB_OUTPUT" 形式
if echo "$CHAT_SURFACE" | grep -E 'echo[[:space:]]+"language=' > /dev/null; then
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

# === Issue #135: `@vibehawk review` 再レビュー分岐の検証 ===
# 利用者が指摘対応後に再レビューを依頼する正規導線として、chat 経路で
# `@vibehawk review` コマンドを認識し、bundled review POST + check-runs POST 経路に
# 切り替える分岐が実装されていることを検証する。
#
# セキュリティ設計（合議制レビュー H-1 への対応）:
#   - Claude prompt は API を呼ばず、event / body の 2 ファイルに payload を書く
#   - 後続 workflow step が payload を validate し、bundled review POST + check-runs POST を
#     決定論的に実行する（Issue #121-C1 fix と同じ思想）
#   - これによりプロンプト注入経由の任意 API 操作（labels / merge / issue-comments など
#     5 大方針 5 抵触エンドポイントの POST）を構造的に防止する
echo "=== Issue #135: @vibehawk review 再レビュー分岐 検証 ==="

# prompt に IS_REVIEW_REQUEST 環境変数（@vibehawk review 検知結果）が渡される
if grep -F "IS_REVIEW_REQUEST:" "$CHAT_WORKFLOW" > /dev/null && \
   grep -F "contains(github.event.comment.body, '@vibehawk review')" "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に IS_REVIEW_REQUEST (contains '@vibehawk review') が渡される（Issue #135）"
else
  fail "prompt に IS_REVIEW_REQUEST が渡されていない（Issue #135、@vibehawk review コマンド検知の前提）"
fi

# prompt に HEAD_SHA 環境変数（workflow step pr_head が fetch した値）が渡される
if grep -F 'HEAD_SHA: ${{ steps.pr_head.outputs.head_sha }}' "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に HEAD_SHA (steps.pr_head.outputs.head_sha) が渡される（Issue #135 セキュリティ修正、Claude 側で gh pr view を呼ばせない）"
else
  fail "prompt に HEAD_SHA が steps.pr_head.outputs.head_sha 経由で渡されていない（Issue #135 セキュリティ修正）"
fi

# prompt に再レビューモード判定指示が含まれる
if grep -F "再レビューモード" "$CHAT_WORKFLOW" > /dev/null && \
   grep -F "@vibehawk review" "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に再レビューモード分岐指示が含まれる（Issue #135）"
else
  fail "prompt に再レビューモード分岐指示が含まれない（Issue #135）"
fi

# prompt に payload ファイル出力指示が含まれる（API 呼び出しは行わない）
if grep -F '/tmp/vibehawk-chat-review-event.txt' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F '/tmp/vibehawk-chat-review-body.txt' "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に payload ファイル (event.txt / body.txt) 出力指示が含まれる（Issue #135 セキュリティ修正、Claude は API を呼ばない）"
else
  fail "prompt に payload ファイル出力指示が含まれない（Issue #135 セキュリティ修正の前提）"
fi

# prompt に再レビュー時の event 判定指示（APPROVE / REQUEST_CHANGES）が含まれる
if grep -F 'REQUEST_CHANGES' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F 'APPROVE' "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に再レビュー event 判定（APPROVE / REQUEST_CHANGES）が含まれる（Issue #135）"
else
  fail "prompt に再レビュー event 判定が含まれない（Issue #135）"
fi

# prompt に SHA マーカー注入指示（再レビューでも Issue #57 と整合）
if grep -F 'vibehawk:summary' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F 'vibehawk:sha=' "$CHAT_WORKFLOW" > /dev/null; then
  pass "再レビュー prompt に種別マーカー / SHA マーカー注入指示が含まれる（Issue #57 / #135）"
else
  fail "再レビュー prompt にマーカー注入指示が含まれない（Issue #57 / #135、インクリメンタルレビュー判定の前提）"
fi

# prompt に外部 URL / 外部画像の埋め込み禁止指示（合議制レビュー M-2 への対応）
if grep -F '外部 URL' "$CHAT_WORKFLOW" > /dev/null || \
   grep -F '外部画像' "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に外部 URL / 外部画像の埋め込み禁止指示が含まれる（Issue #135、check-run summary 経由の情報漏洩防止）"
else
  fail "prompt に外部 URL / 外部画像の埋め込み禁止指示が含まれない（Issue #135）"
fi

# === Issue #135 セキュリティ修正: prompt が API を呼ばないことの保証 ===

# prompt 部分とそれ以外を分離（review.yml と同じパターン）
CHAT_PROMPT="$(awk '/prompt:[[:space:]]*\|/{flag=1; next} /^[[:space:]]+claude_args:/{flag=0} flag' "$CHAT_WORKFLOW")"
CHAT_POST_PROMPT="$(awk '/^[[:space:]]+claude_args:/{flag=1} flag' "$CHAT_WORKFLOW")"

# prompt 内に check-runs POST 指示は **存在しない** こと（review.yml の Issue #121-C1 fix を踏襲）
if echo "$CHAT_PROMPT" | grep -F 'gh api -X POST' | grep -F 'check-runs' > /dev/null; then
  fail "prompt 内に check-runs POST 指示が混入している（Issue #135、workflow step に移管する Issue #121-C1 fix 思想と整合せず）"
else
  pass "prompt 内に check-runs POST 指示が含まれない（Issue #135、workflow step に移管）"
fi

# prompt 内に bundled review POST 指示も **存在しない** こと（Issue #135 セキュリティ修正、
# H-1 への対応: Claude prompt から任意 API を呼ばせない）
if echo "$CHAT_PROMPT" | grep -F 'gh api -X POST' | grep -F 'pulls' | grep -F 'reviews' > /dev/null; then
  fail "prompt 内に bundled review POST 指示が混入している（Issue #135 セキュリティ修正、workflow step post_review に移管すべき）"
else
  pass "prompt 内に bundled review POST 指示が含まれない（Issue #135 セキュリティ修正、workflow step に移管）"
fi

# === Issue #135: pr_head workflow step（HEAD SHA を workflow 側で fetch） ===

if grep -F 'id: pr_head' "$CHAT_WORKFLOW" > /dev/null; then
  pass "pr_head workflow step が存在する（Issue #135、HEAD SHA を workflow 側で fetch）"
else
  fail "pr_head workflow step が存在しない（Issue #135、Claude prompt 内で gh pr view を呼ばせないための前提）"
fi

# pr_head step は @vibehawk review + PR + secrets ready のときのみ実行
PR_HEAD_BLOCK="$(awk '/id: pr_head/,/^[[:space:]]+- name:/' "$CHAT_WORKFLOW")"
if echo "$PR_HEAD_BLOCK" | grep -F "steps.check_secrets.outputs.ready == 'true'" > /dev/null && \
   echo "$PR_HEAD_BLOCK" | grep -F "contains(github.event.comment.body, '@vibehawk review')" > /dev/null && \
   echo "$PR_HEAD_BLOCK" | grep -F "github.event.issue.pull_request != null" > /dev/null; then
  pass "pr_head step の起動条件が secrets ready + @vibehawk review + PR である（Issue #135）"
else
  fail "pr_head step の起動条件が不適切（Issue #135）"
fi

# === Issue #135 セキュリティ修正: bundled review POST workflow step ===

# bundled review POST が後続 workflow step に存在
# Issue #177: シェル本体は scripts/ci/vibehawk-chat/post-bundled-review.sh に切り出し済み
if echo "$CHAT_SURFACE" | grep -F 'gh api -X POST' | grep -F 'pulls' | grep -F 'reviews' > /dev/null; then
  pass "claude-code-action 後の workflow step に bundled review POST が含まれる（Issue #135 セキュリティ修正、scripts/ci/vibehawk-chat/post-bundled-review.sh）"
else
  fail "claude-code-action 後の workflow step に bundled review POST が含まれない（Issue #135 セキュリティ修正の前提）"
fi

# bundled review POST step は payload ファイルを validate する（event 値検証）
if echo "$CHAT_SURFACE" | grep -F 'APPROVE' > /dev/null && \
   echo "$CHAT_SURFACE" | grep -F 'REQUEST_CHANGES' > /dev/null && \
   echo "$CHAT_SURFACE" | grep -F '不正な event 値' > /dev/null; then
  pass "bundled review POST step が event 値を validate する（APPROVE / REQUEST_CHANGES のみ許可、Issue #135 セキュリティ修正）"
else
  fail "bundled review POST step が event 値を validate していない（Issue #135 セキュリティ修正）"
fi

# bundled review POST step は App Installation Token を使う（vibehawk-for-<owner>[bot] 名義で投稿するため）
POST_REVIEW_BLOCK="$(awk '/id: post_review/,/^[[:space:]]+- name:/' "$CHAT_WORKFLOW")"
if [[ -z "$POST_REVIEW_BLOCK" ]]; then
  # 末尾 step の場合 awk が次の `- name:` を見つけられない → ファイル末尾までを切る
  POST_REVIEW_BLOCK="$(awk '/id: post_review/,0' "$CHAT_WORKFLOW")"
fi
if echo "$POST_REVIEW_BLOCK" | grep -F 'steps.app-token.outputs.token' > /dev/null; then
  pass "bundled review POST step が App Installation Token を使用（Issue #135、vibehawk-for-<owner>[bot] 名義投稿）"
else
  fail "bundled review POST step が App Installation Token を使用していない（Issue #135、bot 名義一貫性）"
fi

# === Issue #135: check-runs POST step（status check 更新） ===

# 後続 workflow step に check-runs POST が含まれる
# Issue #177: シェル本体は scripts/ci/vibehawk-chat/post-status-check.sh に切り出し済み
if echo "$CHAT_SURFACE" | grep -F 'gh api -X POST' | grep -F 'check-runs' > /dev/null; then
  pass "claude-code-action 後の workflow step に check-runs POST が含まれる（Issue #135、scripts/ci/vibehawk-chat/post-status-check.sh）"
else
  fail "claude-code-action 後の workflow step に check-runs POST が含まれない（Issue #135、@vibehawk review で check が更新できない）"
fi

# 後続 step の check run name は "vibehawk" 固定（branch protection との一致のため）
if echo "$CHAT_SURFACE" | grep -E 'name="vibehawk"|name=vibehawk' > /dev/null; then
  pass "後続 step に check run name=\"vibehawk\" 固定指定が含まれる（Issue #135、branch protection 一致）"
else
  fail "後続 step に check run name=\"vibehawk\" 固定指定が含まれない（Issue #135）"
fi

# 後続 step の status="completed" 固定
if echo "$CHAT_SURFACE" | grep -F 'status="completed"' > /dev/null; then
  pass "後続 step に status=\"completed\" 固定指定が含まれる（Issue #135）"
else
  fail "後続 step に status=\"completed\" 固定指定が含まれない（Issue #135）"
fi

# 後続 step の conclusion 導出ロジック（APPROVED→success / CHANGES_REQUESTED→failure / 他→neutral）
if echo "$CHAT_SURFACE" | grep -F 'APPROVED)' > /dev/null && \
   echo "$CHAT_SURFACE" | grep -F 'CHANGES_REQUESTED)' > /dev/null && \
   echo "$CHAT_SURFACE" | grep -E 'conclusion="success"' > /dev/null && \
   echo "$CHAT_SURFACE" | grep -E 'conclusion="failure"' > /dev/null && \
   echo "$CHAT_SURFACE" | grep -E 'conclusion="neutral"' > /dev/null; then
  pass "後続 step に conclusion 導出ロジック（APPROVED→success / CHANGES_REQUESTED→failure / 他→neutral）が含まれる（Issue #135）"
else
  fail "後続 step に conclusion 導出ロジックが含まれない（Issue #135、決定論的 status check の前提）"
fi

# check-runs step は @vibehawk review コマンドかつ PR の場合のみ実行される
if echo "$CHAT_POST_PROMPT" | grep -F "contains(github.event.comment.body, '@vibehawk review')" > /dev/null && \
   echo "$CHAT_POST_PROMPT" | grep -F "github.event.issue.pull_request != null" > /dev/null; then
  pass "後続 check-runs step は @vibehawk review かつ PR の場合のみ実行（Issue #135）"
else
  fail "後続 check-runs step の起動条件が不適切（Issue #135、通常 chat 応答時にも誤発火する可能性）"
fi

# check-runs step は GITHUB_TOKEN を使う（App permission 状態に依存しない、Issue #121-C1 fix と同じ理由）
if echo "$CHAT_POST_PROMPT" | grep -E 'GH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*secrets\.GITHUB_TOKEN[[:space:]]*\}\}' > /dev/null; then
  pass "後続 check-runs step が secrets.GITHUB_TOKEN を使用（Issue #135、App permission 状態に依存しない）"
else
  fail "後続 check-runs step が secrets.GITHUB_TOKEN を使用していない（Issue #135、checks: write はデフォルト workflow token に付与する設計）"
fi

# substantive review filter（@vibehawk review 経路でも空 COMMENTED 副産物の誤拾い対策、Issue #121 追加修正を踏襲）
if echo "$CHAT_SURFACE" | grep -F 'substantive_review_json' > /dev/null; then
  pass "後続 check-runs step に substantive_review_json 変数が導入されている（Issue #135、Issue #121 追加修正の踏襲）"
else
  fail "後続 check-runs step に substantive_review_json 変数が導入されていない（Issue #135）"
fi

if echo "$CHAT_SURFACE" | grep -F '.state == "APPROVED" or .state == "CHANGES_REQUESTED"' > /dev/null; then
  pass "substantive review filter が state APPROVED/CHANGES_REQUESTED で絞り込む（Issue #135、Issue #121 追加修正の踏襲）"
else
  fail "substantive review filter が state APPROVED/CHANGES_REQUESTED で絞り込んでいない（Issue #135）"
fi

# === Issue #290（epic #289 子1）: @vibehawk review の diff-aware 分岐の検証 ===
# `@vibehawk review` で前回レビュー以降のコミット差分の有無を判定し、差分なしなら
# LLM 非実行の verdict 再評価経路へ、差分ありなら従来の増分 LLM レビュー経路へ分岐する。
echo "=== Issue #290: @vibehawk review diff-aware 分岐 検証 ==="

# 差分判定 step（review_diff）が存在し detect-review-diff.sh を呼ぶ
if grep -F 'id: review_diff' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F 'bash scripts/ci/vibehawk-chat/detect-review-diff.sh' "$CHAT_WORKFLOW" > /dev/null; then
  pass "差分判定 step (review_diff) が detect-review-diff.sh を呼ぶ（Issue #290）"
else
  fail "差分判定 step (review_diff) が存在しない（Issue #290）"
fi

# claude-code-action step が差分なし(@vibehawk review + PR + diff_exists=false)時にスキップされる
if grep -F "steps.review_diff.outputs.diff_exists == 'false'" "$CHAT_WORKFLOW" > /dev/null; then
  pass "差分なし時に claude-code-action をスキップする gate (diff_exists == 'false') が存在する（Issue #290、LLM 非実行）"
else
  fail "claude-code-action の差分なしスキップ gate が存在しない（Issue #290、LLM 非実行が達成されない）"
fi

# bundled review POST は差分あり(diff_exists=true)時のみ実行される
if grep -F "steps.review_diff.outputs.diff_exists == 'true'" "$CHAT_WORKFLOW" > /dev/null; then
  pass "bundled review POST が差分あり(diff_exists == 'true')時のみ実行される gate が存在する（Issue #290）"
else
  fail "bundled review POST の差分あり gate が存在しない（Issue #290）"
fi

# 差分なし経路の verdict 再評価 step（reverdict）が re-evaluate-verdict.sh を呼ぶ
if grep -F 'id: reverdict' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F 'bash scripts/ci/vibehawk-chat/re-evaluate-verdict.sh' "$CHAT_WORKFLOW" > /dev/null; then
  pass "差分なし経路の verdict 再評価 step (reverdict) が re-evaluate-verdict.sh を呼ぶ（Issue #290）"
else
  fail "差分なし経路の verdict 再評価 step が存在しない（Issue #290）"
fi

# 差分なし経路の再チェック通知 step が post-recheck-notice.sh を呼ぶ
if grep -F 'bash scripts/ci/vibehawk-chat/post-recheck-notice.sh' "$CHAT_WORKFLOW" > /dev/null; then
  pass "差分なし経路の再チェック通知 step が post-recheck-notice.sh を呼ぶ（Issue #290）"
else
  fail "差分なし経路の再チェック通知 step が存在しない（Issue #290）"
fi

# re-evaluate-verdict / detect-review-diff は LLM・claude -p・npx・bunx を呼ばない（API コスト 0）
REVERDICT_CONTENT="$(cat "${CHAT_SCRIPTS_DIR}/re-evaluate-verdict.sh" "${CHAT_SCRIPTS_DIR}/detect-review-diff.sh" 2>/dev/null || true)"
if echo "$REVERDICT_CONTENT" | grep -E 'claude -p|npx|bunx|ANTHROPIC_API_KEY' > /dev/null; then
  fail "差分なし経路スクリプトに LLM 呼び出し（claude -p / npx / bunx）が混入している（Issue #290、コスト 0 の前提崩壊）"
else
  pass "差分なし経路スクリプトに LLM 呼び出しが含まれない（Issue #290、gh api のみで API コスト 0）"
fi

# === Issue #291（epic #289 子2）: @vibehawk full review コマンドの検証 ===
# 過去指摘を無視した PR 全体再レビュー。@vibehawk review（増分）と排他で衝突しない。
echo "=== Issue #291: @vibehawk full review 検証 ==="

# IS_FULL_REVIEW env が prompt に渡る
if grep -F "IS_FULL_REVIEW:" "$CHAT_WORKFLOW" > /dev/null && \
   grep -F "contains(github.event.comment.body, '@vibehawk full review')" "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に IS_FULL_REVIEW (contains '@vibehawk full review') が渡される（Issue #291）"
else
  fail "prompt に IS_FULL_REVIEW が渡されていない（Issue #291、full review コマンド検知の前提）"
fi

# prompt に全体再レビューモード分岐と「過去指摘無視・全件評価」指示が含まれる
if grep -F "全体再レビューモード" "$CHAT_WORKFLOW" > /dev/null && \
   grep -F "過去の vibehawk 指摘" "$CHAT_WORKFLOW" > /dev/null; then
  pass "prompt に全体再レビューモード（過去指摘無視・全件評価）が含まれる（Issue #291）"
else
  fail "prompt に全体再レビューモードの分岐指示が含まれない（Issue #291）"
fi

# pr_head が full review でも発火する
PR_HEAD_FULL_BLOCK="$(awk '/id: pr_head/,/run: bash/' "$CHAT_WORKFLOW")"
if echo "$PR_HEAD_FULL_BLOCK" | grep -F "contains(github.event.comment.body, '@vibehawk full review')" > /dev/null; then
  pass "pr_head step が @vibehawk full review でも発火する（Issue #291、HEAD SHA 取得）"
else
  fail "pr_head step が @vibehawk full review で発火しない（Issue #291）"
fi

# post_review が full review でも発火する
POST_REVIEW_FULL_BLOCK="$(awk '/id: post_review/,/run: bash/' "$CHAT_WORKFLOW")"
if echo "$POST_REVIEW_FULL_BLOCK" | grep -F "contains(github.event.comment.body, '@vibehawk full review')" > /dev/null; then
  pass "post_review step が @vibehawk full review でも bundled review を post する（Issue #291）"
else
  fail "post_review step が @vibehawk full review で発火しない（Issue #291）"
fi

# post-status-check が full review でも発火する
STATUS_CHECK_BLOCK="$(awk '/status check を post（@vibehawk/,/run: bash/' "$CHAT_WORKFLOW")"
if echo "$STATUS_CHECK_BLOCK" | grep -F "contains(github.event.comment.body, '@vibehawk full review')" > /dev/null; then
  pass "post-status-check step が @vibehawk full review でも status check を更新する（Issue #291）"
else
  fail "post-status-check step が @vibehawk full review で発火しない（Issue #291）"
fi

# 衝突しないこと: review_diff / reverdict gate は @vibehawk full review を含まない（増分経路と排他）
REVIEW_DIFF_BLOCK="$(awk '/id: review_diff/,/run: bash/' "$CHAT_WORKFLOW")"
REVERDICT_BLOCK="$(awk '/id: reverdict/,/run: bash/' "$CHAT_WORKFLOW")"
if ! echo "$REVIEW_DIFF_BLOCK" | grep -F "@vibehawk full review" > /dev/null && \
   ! echo "$REVERDICT_BLOCK" | grep -F "@vibehawk full review" > /dev/null; then
  pass "review_diff / reverdict は @vibehawk full review を gate に含まない（増分経路と衝突しない、Issue #291）"
else
  fail "review_diff / reverdict が full review を巻き込んでいる（Issue #291、増分経路と衝突）"
fi

# === Issue #292（epic #289 子3）: @vibehawk resolve コマンドの検証 ===
# vibehawk 自身の未解決スレッドを一括 resolve。LLM 不要の決定論的操作。
echo "=== Issue #292: @vibehawk resolve 検証 ==="

# resolve step が resolve-own-threads.sh を呼ぶ
if grep -F 'id: resolve_threads' "$CHAT_WORKFLOW" > /dev/null && \
   grep -F 'bash scripts/ci/vibehawk-chat/resolve-own-threads.sh' "$CHAT_WORKFLOW" > /dev/null; then
  pass "resolve step (resolve_threads) が resolve-own-threads.sh を呼ぶ（Issue #292）"
else
  fail "resolve step が存在しない（Issue #292）"
fi

# resolve step は @vibehawk resolve + PR で発火する
RESOLVE_BLOCK="$(awk '/id: resolve_threads/,/run: bash/' "$CHAT_WORKFLOW")"
if echo "$RESOLVE_BLOCK" | grep -F "contains(github.event.comment.body, '@vibehawk resolve')" > /dev/null && \
   echo "$RESOLVE_BLOCK" | grep -F "github.event.issue.pull_request != null" > /dev/null; then
  pass "resolve step の起動条件が @vibehawk resolve + PR（Issue #292）"
else
  fail "resolve step の起動条件が不適切（Issue #292）"
fi

# claude-code-action が resolve でスキップされる（LLM 不要）
CLAUDE_SKIP_BLOCK="$(awk '/- name: claude-code-action でチャット応答/,/uses: anthropics/' "$CHAT_WORKFLOW")"
if echo "$CLAUDE_SKIP_BLOCK" | grep -F "@vibehawk resolve" > /dev/null; then
  pass "claude-code-action が @vibehawk resolve でスキップされる（Issue #292、LLM 不要）"
else
  fail "claude-code-action の resolve スキップ条件が不在（Issue #292）"
fi

# reverdict が resolve でも発火する（全解決→APPROVE 再評価）
REVERDICT_RESOLVE_BLOCK="$(awk '/id: reverdict/,/run: bash/' "$CHAT_WORKFLOW")"
if echo "$REVERDICT_RESOLVE_BLOCK" | grep -F "contains(github.event.comment.body, '@vibehawk resolve')" > /dev/null; then
  pass "reverdict step が @vibehawk resolve でも verdict を再評価する（Issue #292）"
else
  fail "reverdict step が @vibehawk resolve で発火しない（Issue #292）"
fi

# resolve-own-threads は二重防御を持つ（node_id glob + author 再確認）
RESOLVE_SCRIPT="${CHAT_SCRIPTS_DIR}/resolve-own-threads.sh"
if grep -F '[!A-Za-z0-9+/=_-]' "$RESOLVE_SCRIPT" > /dev/null && \
   grep -F 'EXPECTED_LOGIN' "$RESOLVE_SCRIPT" > /dev/null; then
  pass "resolve-own-threads が二重防御（node_id glob + author 再確認）を持つ（Issue #292）"
else
  fail "resolve-own-threads の二重防御が不足（Issue #292、誤 resolve リスク）"
fi

# resolve-own-threads は claude -p / npx / bunx を呼ばない（決定論的）
if grep -E 'claude -p|npx|bunx|ANTHROPIC_API_KEY' "$RESOLVE_SCRIPT" > /dev/null; then
  fail "resolve-own-threads に LLM 呼び出しが混入している（Issue #292）"
else
  pass "resolve-own-threads は LLM を呼ばない決定論的 step（Issue #292）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
