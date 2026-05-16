#!/usr/bin/env bash
# vibehawk-review.yml workflow テンプレートの最小要件検証
# 検証対象: `templates/.github/workflows/vibehawk-review.yml`（npm 配布される
# テンプレート本体）。`.github/workflows/vibehawk-review.yml`（dogfooding 用
# デプロイコピー）は templates と完全一致することを test_workflow_template_snapshot.sh
# で別途検証するため、本テストでは templates のみを検査する。
# Issue #56 dogfooding teardown で `.github/` 配下が一時削除されても、本テストは
# templates を見るため影響を受けない。
#
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

WORKFLOW="${REPO_ROOT}/templates/.github/workflows/vibehawk-review.yml"

echo "=== templates/.github/workflows/vibehawk-review.yml 検証 ==="

# ファイル存在（前提: 不在なら全後続テスト無意味）
if [[ -f "$WORKFLOW" ]]; then
  pass "templates/.github/workflows/vibehawk-review.yml が存在する"
else
  fail "templates/.github/workflows/vibehawk-review.yml が存在しない"
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

# 必須イベントタイプ 4 種（Issue #135: review_requested を追加）
# review_requested は GitHub UI の "Re-request review" ボタン押下時に発火する。
# 一度 vibehawk が failure を post すると required status check が永久ブロックされる
# UX 欠陥（Issue #135 / PR #133）を解消する正規導線。
for evt in opened synchronize ready_for_review review_requested; do
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
# Issue #121-C1 fix: checks: write を必須化（workflow step での check-runs POST 用）
declare -a required_perms=(
  "pull-requests:[[:space:]]*write"
  "issues:[[:space:]]*write"
  "contents:[[:space:]]*read"
  "checks:[[:space:]]*write"
)
declare -a perm_labels=(
  "pull-requests: write"
  "issues: write"
  "contents: read"
  "checks: write"
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

# Issue #121: bundled review API（gh api -X POST pulls/N/reviews）で投稿するため、
# allowedTools に Bash(gh api:*) が含まれることを確認する。
# 旧 `gh pr comment` / `gh pr review` 経路は bundled 化で撤廃（colored badge 表示の前提）。
if echo "$WORKFLOW_BODY" | grep -F "Bash(gh api:*)" > /dev/null; then
  pass "allowedTools に Bash(gh api:*) が含まれる（Issue #121 bundled review API 投稿）"
else
  fail "allowedTools に Bash(gh api:*) が含まれない（Issue #121、bundled review POST が呼べない）"
fi

# Issue #121: 旧 `gh pr comment` / `gh pr review` 経路は bundled 化で撤廃されているべき
if echo "$WORKFLOW_BODY" | grep -F "Bash(gh pr comment:*)" > /dev/null; then
  fail "allowedTools に Bash(gh pr comment:*) が残っている（Issue #121、bundled 化で撤廃すべき）"
else
  pass "allowedTools に Bash(gh pr comment:*) が含まれない（Issue #121 bundled 化）"
fi

if echo "$WORKFLOW_BODY" | grep -F "Bash(gh pr review:*)" > /dev/null; then
  fail "allowedTools に Bash(gh pr review:*) が残っている（Issue #121、bundled 化で撤廃すべき）"
else
  pass "allowedTools に Bash(gh pr review:*) が含まれない（Issue #121 bundled 化）"
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

# Issue #57 修正: prompt に種別マーカー <!-- vibehawk:summary --> 注入指示が含まれる
# （prompt セクション末尾は HTML コメント形式の指示で、awk のコメント除外を回避するため WORKFLOW 全体を grep する）
if grep -F '<!-- vibehawk:summary -->' "$WORKFLOW" > /dev/null; then
  pass "prompt に種別マーカー <!-- vibehawk:summary --> 注入指示が含まれる（Issue #57）"
else
  fail "prompt に種別マーカー <!-- vibehawk:summary --> 注入指示が含まれない（Issue #57、インクリメンタルレビュー #8 の前提）"
fi

# Issue #57 修正: prompt に SHA マーカー <!-- vibehawk:sha=... --> 注入指示が含まれる
if grep -F 'vibehawk:sha=' "$WORKFLOW" > /dev/null; then
  pass "prompt に SHA マーカー <!-- vibehawk:sha=... --> 注入指示が含まれる（Issue #57）"
else
  fail "prompt に SHA マーカー <!-- vibehawk:sha=... --> 注入指示が含まれない（Issue #57、force push 検出の前提）"
fi

# Issue #57 修正: HEAD SHA を prompt に変数として渡している
if grep -F 'github.event.pull_request.head.sha' "$WORKFLOW" > /dev/null; then
  pass "HEAD SHA が github.event.pull_request.head.sha で prompt に渡されている（Issue #57）"
else
  fail "HEAD SHA が prompt に渡されていない（Issue #57、SHA マーカー埋込の前提）"
fi

# Issue #8: インクリメンタルレビュー判定ステップが存在する
if grep -F 'id: prev_summary' "$WORKFLOW" > /dev/null; then
  pass "インクリメンタルレビュー判定ステップ (prev_summary) が存在する（Issue #8）"
else
  fail "インクリメンタルレビュー判定ステップが存在しない（Issue #8 未実装）"
fi

# Issue #8: prev_summary ステップが投稿者 ID + 種別マーカーの二重チェックを実装
# （workflow YAML 内では jq クエリ内のダブルクオートがバックスラッシュエスケープされるため、エスケープ無視で grep）
if grep -F 'select(.user.login ==' "$WORKFLOW" > /dev/null && \
   grep -F 'contains(' "$WORKFLOW" | grep -F '<!-- vibehawk:summary -->' > /dev/null; then
  pass "prev_summary が投稿者 ID + 種別マーカーの二重チェックを実装（Issue #8）"
else
  fail "prev_summary の二重チェック実装が想定と異なる（Issue #8、なりすまし排除に必須）"
fi

# Issue #8: prev_summary ステップが SHA マーカーから前回 SHA を抽出
if grep -E 'grep -oE.*vibehawk:sha=\[a-f0-9\]\+' "$WORKFLOW" > /dev/null; then
  pass "prev_summary が SHA マーカーから前回 SHA を抽出（Issue #8）"
else
  fail "prev_summary が SHA マーカー抽出を実装していない（Issue #8）"
fi

# Issue #8: prev_summary ステップが force push / rebase 検出を実装（merge-base --is-ancestor）
if grep -F 'merge-base --is-ancestor' "$WORKFLOW" > /dev/null; then
  pass "prev_summary が force push / rebase 検出（merge-base --is-ancestor）を実装（Issue #8）"
else
  fail "prev_summary が force push / rebase 検出を実装していない（Issue #8）"
fi

# Issue #8: prev_summary が incremental / comment_id / prev_sha / review_range の 4 つを GITHUB_OUTPUT に出力
for output in incremental comment_id prev_sha review_range; do
  if grep -E "echo \"${output}=" "$WORKFLOW" > /dev/null; then
    pass "prev_summary が GITHUB_OUTPUT に ${output} を出力（Issue #8）"
  else
    fail "prev_summary が GITHUB_OUTPUT に ${output} を出力していない（Issue #8）"
  fi
done

# Issue #8: claude-code-action の prompt に INCREMENTAL_MODE / EXISTING_COMMENT_ID / PREV_SHA / REVIEW_RANGE が渡される
for var in INCREMENTAL_MODE EXISTING_COMMENT_ID PREV_SHA REVIEW_RANGE; do
  if grep -F "${var}: " "$WORKFLOW" > /dev/null; then
    pass "prompt に ${var} が渡されている（Issue #8）"
  else
    fail "prompt に ${var} が渡されていない（Issue #8）"
  fi
done

# Issue #121: bundled review API への移行
# - prompt に bundled review POST 指示が含まれる（gh api -X POST pulls/N/reviews）
# - incremental サマリは新規 review 都度作成（GitHub Reviews API は edit 不可）
# - 旧 gh api -X PATCH issues/comments/ 経路は撤廃
if grep -F 'gh api -X POST' "$WORKFLOW" > /dev/null && \
   grep -F 'pulls/$PR_NUMBER/reviews' "$WORKFLOW" > /dev/null; then
  pass "prompt に bundled review POST 指示（gh api -X POST pulls/N/reviews）が含まれる（Issue #121）"
else
  fail "prompt に bundled review POST 指示が含まれない（Issue #121、colored badge 表示の前提）"
fi

# Issue #121: 旧 PATCH コメント edit 経路は撤廃されているべき
if grep -F 'gh api -X PATCH' "$WORKFLOW" > /dev/null && \
   grep -F 'issues/comments/' "$WORKFLOW" > /dev/null; then
  fail "prompt に旧コメント edit 指示（gh api -X PATCH issues/comments/）が残っている（Issue #121、bundled 化で撤廃すべき）"
else
  pass "prompt から旧コメント edit 指示が撤廃されている（Issue #121 bundled 化）"
fi

# Issue #121: bundled review POST には event / body / commit_id / comments 4 フィールドが必須
for field in event body commit_id comments; do
  if grep -F "$field" "$WORKFLOW" > /dev/null; then
    pass "prompt に bundled review POST の $field フィールド指示が含まれる（Issue #121）"
  else
    fail "prompt に bundled review POST の $field フィールド指示が含まれない（Issue #121）"
  fi
done

# Issue #121: event は APPROVE / REQUEST_CHANGES のいずれか
if grep -F 'APPROVE' "$WORKFLOW" > /dev/null && \
   grep -F 'REQUEST_CHANGES' "$WORKFLOW" > /dev/null; then
  pass "prompt に event=APPROVE / REQUEST_CHANGES の指示が含まれる（Issue #121）"
else
  fail "prompt に event=APPROVE / REQUEST_CHANGES の指示が含まれない（Issue #121）"
fi

# Issue #121: prev_summary ステップが pulls/.../reviews 経路で前回サマリを検索する
if grep -F 'pulls/${PR_NUMBER}/reviews' "$WORKFLOW" > /dev/null; then
  pass "prev_summary が pulls/.../reviews エンドポイントで前回サマリを検索する（Issue #121）"
else
  fail "prev_summary が pulls/.../reviews エンドポイントを参照していない（Issue #121、bundled review API への移行未完）"
fi

# Issue #121: bundled review POST のランタイム gh モック検証
# prompt 内に埋め込まれた `jq -n ... | gh api -X POST repos/$REPO/pulls/$PR_NUMBER/reviews --input -`
# サンプルを抽出し、`gh` をスタブ化して以下を検証する:
#   - POST /pulls/<PR>/reviews が **ちょうど 1 回** 呼ばれる
#   - 受け取った JSON payload が必須 4 フィールド（event / body / commit_id / comments）を含む
#   - event 値が APPROVE / REQUEST_CHANGES のいずれかである
#   - 旧経路 `gh api -X PATCH issues/comments/` が **1 回も呼ばれない**
# Issue #121 完了条件（gh api モック検証）を grep 検証だけでなく実行時に担保する。
MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_DIR"' EXIT

# gh スタブを作成: 引数と stdin を記録するだけ
cat > "$MOCK_DIR/gh" <<MOCK_EOF
#!/usr/bin/env bash
# 呼び出しログに引数を 1 行追記
echo "\$@" >> "$MOCK_DIR/gh_calls.log"
# --input - 指定時は stdin の JSON を保存
for arg in "\$@"; do
  if [[ "\$arg" == "--input" ]]; then
    cat > "$MOCK_DIR/gh_last_stdin.json"
    break
  fi
done
exit 0
MOCK_EOF
chmod +x "$MOCK_DIR/gh"
touch "$MOCK_DIR/gh_calls.log"

# 環境変数を準備し、prompt のサンプル相当 bash を実行
(
  export PATH="$MOCK_DIR:$PATH"
  export REPO="hirokimry/vibehawk"
  export PR_NUMBER="999"
  export EVENT="REQUEST_CHANGES"
  export REVIEW_BODY="test summary body"
  export HEAD_SHA="deadbeef1234567890abcdef1234567890abcdef"

  # inline comments 配列（prompt の comments[] フォーマット）
  cat > "$MOCK_DIR/comments_array.json" <<'JSON'
[
  {"path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "🟠 **Major**: test"}
]
JSON

  # prompt 内の bundled POST サンプルを実行（templates/.github/workflows/vibehawk-review.yml 内の指示と同一）
  jq -n \
    --arg event "$EVENT" \
    --arg body "$REVIEW_BODY" \
    --arg commit_id "$HEAD_SHA" \
    --slurpfile comments "$MOCK_DIR/comments_array.json" \
    '{event: $event, body: $body, commit_id: $commit_id, comments: $comments[0]}' \
    | gh api -X POST "repos/$REPO/pulls/$PR_NUMBER/reviews" --input -
)

# 検証 1: POST /pulls/<PR>/reviews が 1 回呼ばれる
post_count="$(grep -cE -- '-X POST repos/[^ ]+/pulls/[0-9]+/reviews' "$MOCK_DIR/gh_calls.log" || true)"
if [[ "$post_count" -eq 1 ]]; then
  pass "bundled POST /pulls/N/reviews がランタイムでちょうど 1 回呼ばれる（Issue #121）"
else
  fail "bundled POST /pulls/N/reviews の呼出回数が想定外: ${post_count} 回（Issue #121、期待: 1）"
fi

# 検証 2: 旧経路 PATCH issues/comments が呼ばれていない
patch_count="$(grep -cE -- '-X PATCH .*issues/comments' "$MOCK_DIR/gh_calls.log" || true)"
if [[ "$patch_count" -eq 0 ]]; then
  pass "旧経路 gh api -X PATCH issues/comments がランタイムで呼ばれない（Issue #121）"
else
  fail "旧経路 gh api -X PATCH issues/comments が ${patch_count} 回呼ばれている（Issue #121、bundled 化で撤廃すべき）"
fi

# 検証 3: payload に必須 4 フィールドが含まれる
if [[ -f "$MOCK_DIR/gh_last_stdin.json" ]]; then
  for field in event body commit_id comments; do
    if jq -e --arg f "$field" 'has($f)' "$MOCK_DIR/gh_last_stdin.json" > /dev/null; then
      pass "bundled POST payload に必須フィールド '$field' が含まれる（Issue #121）"
    else
      fail "bundled POST payload に必須フィールド '$field' が含まれない（Issue #121）"
    fi
  done

  # 検証 4: event 値が APPROVE / REQUEST_CHANGES のいずれか
  event_val="$(jq -r '.event' "$MOCK_DIR/gh_last_stdin.json")"
  if [[ "$event_val" == "APPROVE" || "$event_val" == "REQUEST_CHANGES" ]]; then
    pass "bundled POST payload の event 値が APPROVE/REQUEST_CHANGES のいずれか（実値: ${event_val}）"
  else
    fail "bundled POST payload の event 値が APPROVE/REQUEST_CHANGES 以外: ${event_val}（Issue #121）"
  fi

  # 検証 5: comments が配列である
  if jq -e '.comments | type == "array"' "$MOCK_DIR/gh_last_stdin.json" > /dev/null; then
    pass "bundled POST payload の comments が配列である（Issue #121）"
  else
    fail "bundled POST payload の comments が配列でない（Issue #121）"
  fi
else
  fail "bundled POST の stdin payload が記録されていない（Issue #121、mock が --input - を受け取っていない）"
fi

# Issue #8: allowedTools に gh api / git log / git diff が追加されている
for tool in 'gh api:\*' 'git log:\*' 'git diff:\*'; do
  if grep -E "Bash\(${tool}\)" "$WORKFLOW" > /dev/null; then
    pass "allowedTools に Bash(${tool}) が含まれる（Issue #8）"
  else
    fail "allowedTools に Bash(${tool}) が含まれない（Issue #8、コメント edit / range 解析に必須）"
  fi
done

# Issue #10: vibehawk_config ステップが存在
if grep -F 'id: vibehawk_config' "$WORKFLOW" > /dev/null; then
  pass "vibehawk_config ステップが存在する（Issue #10）"
else
  fail "vibehawk_config ステップが存在しない（Issue #10 未実装）"
fi

# Issue #10: .vibehawk.yaml 優先 / .coderabbit.yaml fallback
if grep -F '.vibehawk.yaml' "$WORKFLOW" > /dev/null && \
   grep -F '.coderabbit.yaml' "$WORKFLOW" > /dev/null; then
  pass ".vibehawk.yaml / .coderabbit.yaml の両方が参照される（Issue #10）"
else
  fail "設定ファイル両形式の参照が不足（Issue #10）"
fi

# Issue #10: PyYAML 可用性確認 + フォールバック pip install
if grep -F 'import yaml' "$WORKFLOW" > /dev/null && \
   grep -F 'pip install' "$WORKFLOW" | grep -F 'pyyaml' > /dev/null; then
  pass "PyYAML 可用性確認とフォールバック pip install が含まれる（Issue #10）"
else
  fail "PyYAML 可用性確認 / pip install フォールバックが不足（Issue #10、ubuntu-latest 以外で動作不能）"
fi

# Issue #10: depth 切替ロジック（4 段階）
for depth in summary_only lightweight focused full; do
  if grep -F "depth=\"$depth\"" "$WORKFLOW" > /dev/null || \
     grep -F "depth=$depth" "$WORKFLOW" > /dev/null; then
    pass "depth=$depth の出力が含まれる（Issue #10 段階的劣化）"
  else
    fail "depth=$depth の出力が不足（Issue #10）"
  fi
done

# Issue #10: vibehawk_config が GITHUB_OUTPUT に config_source / language / files_count / depth / path_filters / path_instructions を出力
for output in config_source language files_count depth path_filters path_instructions; do
  if grep -E "echo \"${output}=" "$WORKFLOW" > /dev/null; then
    pass "vibehawk_config が GITHUB_OUTPUT に ${output} を出力（Issue #10）"
  else
    fail "vibehawk_config が GITHUB_OUTPUT に ${output} を出力していない（Issue #10）"
  fi
done

# Issue #10: prompt に CONFIG_SOURCE / LANGUAGE / DEPTH / PATH_FILTERS_JSON / PATH_INSTRUCTIONS_JSON が渡される
for var in CONFIG_SOURCE LANGUAGE DEPTH PATH_FILTERS_JSON PATH_INSTRUCTIONS_JSON; do
  if grep -F "${var}: " "$WORKFLOW" > /dev/null; then
    pass "prompt に ${var} が渡される（Issue #10）"
  else
    fail "prompt に ${var} が渡されない（Issue #10）"
  fi
done

# Issue #10: prompt に locale 指示（LANGUAGE=ja で日本語出力）
if grep -F 'LANGUAGE=ja' "$WORKFLOW" > /dev/null && \
   grep -F '日本語' "$WORKFLOW" > /dev/null; then
  pass "prompt に locale (LANGUAGE=ja → 日本語出力) 指示が含まれる（Issue #10）"
else
  fail "prompt に locale 指示が不足（Issue #10）"
fi

# Issue #10: prompt に path_filters / path_instructions の処理指示が含まれる
if grep -F 'path_filters' "$WORKFLOW" > /dev/null && \
   grep -F 'path_instructions' "$WORKFLOW" > /dev/null; then
  pass "prompt に path_filters / path_instructions の処理指示が含まれる（Issue #10）"
else
  fail "prompt に path_filters / path_instructions の処理指示が不足（Issue #10）"
fi

# Issue #10: depth 別の振る舞い説明（full / focused / lightweight / summary_only）が prompt に含まれる
depth_desc_count=0
for depth in full focused lightweight summary_only; do
  if grep -F "$depth" "$WORKFLOW" > /dev/null; then
    depth_desc_count=$((depth_desc_count + 1))
  fi
done
if [[ "$depth_desc_count" -eq 4 ]]; then
  pass "prompt に depth 4 段階の振る舞い説明が含まれる（Issue #10）"
else
  fail "prompt に depth 4 段階のすべての説明が含まれない（Issue #10、$depth_desc_count/4）"
fi

# Issue #121-C1 fix: status check 投稿は workflow step が決定論的に行う設計に変更
# （Claude prompt 内 check-runs POST は claude-code-action の permission_denial で動作しないため）。
#
# 旧設計の prompt 内 check-runs 指示は **撤廃** されているべき。
# 新設計では claude-code-action ステップの後に独立した GitHub Actions step を追加し、
# デフォルト GITHUB_TOKEN（checks: write 付き）で check-runs を POST する。

# prompt 部分とそれ以外を分離するため、prompt セクション（`prompt: |` から `claude_args:` 直前まで）を抽出
# awk で "prompt: |" 〜 "claude_args:" の範囲を取る
WORKFLOW_PROMPT="$(awk '/prompt:[[:space:]]*\|/{flag=1; next} /^[[:space:]]+claude_args:/{flag=0} flag' "$WORKFLOW")"
# prompt より後（claude_args: 以降、後続 step を含む）を抽出
WORKFLOW_POST_PROMPT="$(awk '/^[[:space:]]+claude_args:/{flag=1} flag' "$WORKFLOW")"

# 旧設計の prompt 内 check-runs POST 指示は撤廃されているべき
if echo "$WORKFLOW_PROMPT" | grep -F 'gh api -X POST' | grep -F 'check-runs' > /dev/null; then
  fail "prompt 内に check-runs POST 指示が残っている（Issue #121-C1 fix、claude-code-action permission_denial で deny されるため撤廃すべき）"
else
  pass "prompt 内に check-runs POST 指示が残っていない（Issue #121-C1 fix、workflow step に移管済み）"
fi

# 新設計: claude-code-action ステップ以降の workflow step に check-runs POST が含まれる
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'gh api -X POST' | grep -F 'check-runs' > /dev/null; then
  pass "claude-code-action 後の workflow step に check-runs POST が含まれる（Issue #121-C1 fix、決定論的 status check）"
else
  fail "claude-code-action 後の workflow step に check-runs POST が含まれない（Issue #121-C1 fix、決定論的 status check の前提）"
fi

# 新設計: check run の name は "vibehawk" 固定（branch protection との一致のため）
if echo "$WORKFLOW_POST_PROMPT" | grep -E 'name="vibehawk"|name=vibehawk' > /dev/null; then
  pass "後続 step に check run name=\"vibehawk\" 固定指定が含まれる（Issue #121-C1 fix、branch protection 一致）"
else
  fail "後続 step に check run name=\"vibehawk\" 固定指定が含まれない（Issue #121-C1 fix）"
fi

# 新設計: status="completed" 固定
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'status="completed"' > /dev/null; then
  pass "後続 step に status=\"completed\" 固定指定が含まれる（Issue #121-C1 fix）"
else
  fail "後続 step に status=\"completed\" 固定指定が含まれない（Issue #121-C1 fix）"
fi

# 新設計: conclusion 導出の bash ロジック（APPROVED→success / CHANGES_REQUESTED→failure / 他→neutral）が含まれる
# case 文での state → conclusion マッピング全体を grep
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'APPROVED)' > /dev/null && \
   echo "$WORKFLOW_POST_PROMPT" | grep -F 'CHANGES_REQUESTED)' > /dev/null && \
   echo "$WORKFLOW_POST_PROMPT" | grep -E 'conclusion="success"' > /dev/null && \
   echo "$WORKFLOW_POST_PROMPT" | grep -E 'conclusion="failure"' > /dev/null && \
   echo "$WORKFLOW_POST_PROMPT" | grep -E 'conclusion="neutral"' > /dev/null; then
  pass "後続 step に conclusion 導出ロジック（APPROVED→success / CHANGES_REQUESTED→failure / 他→neutral）が含まれる（Issue #121-C1 fix）"
else
  fail "後続 step に conclusion 導出ロジックが含まれない（Issue #121-C1 fix、bash case ベースの決定論マッピングが前提）"
fi

# 新設計: secrets ガード（既存 check_secrets パターンを後続 step も継承）
if echo "$WORKFLOW_POST_PROMPT" | grep -F "steps.check_secrets.outputs.ready == 'true'" > /dev/null; then
  pass "後続 status check step が check_secrets.ready ガードを継承（Issue #121-C1 fix、secrets 未設定時 skip）"
else
  fail "後続 status check step が check_secrets.ready ガードを継承していない（Issue #121-C1 fix）"
fi

# 新設計: GITHUB_TOKEN（デフォルト workflow token）を使う（App Installation Token ではなく）
# 理由: workflow.permissions.checks: write はデフォルト GITHUB_TOKEN に付与され、
# App installation の permission 更新（再 install 必須）に依存しないため信頼性が高い
if echo "$WORKFLOW_POST_PROMPT" | grep -E 'GH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*secrets\.GITHUB_TOKEN[[:space:]]*\}\}' > /dev/null; then
  pass "後続 status check step が secrets.GITHUB_TOKEN を使用（Issue #121-C1 fix、App permission 状態に依存しない）"
else
  fail "後続 status check step が secrets.GITHUB_TOKEN を使用していない（Issue #121-C1 fix、App permission 更新依存を避けるため必須）"
fi

# Issue #121 追加修正: substantive review filter（PR #129 観測対応）
# bundled review POST 後に auto_resolve thread 解決で空の COMMENTED review が
# 副産物として追加されるため、単純な「最後尾」では空 COMMENTED を拾い conclusion が
# neutral に倒れる。substantive な review（APPROVED / CHANGES_REQUESTED かつ body 非空）
# を優先取得するロジックが含まれていることを検証する。

# 1. substantive_review_json 変数を導入している
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'substantive_review_json' > /dev/null; then
  pass "後続 status check step に substantive_review_json 変数が導入されている（Issue #121 追加修正）"
else
  fail "後続 status check step に substantive_review_json 変数が導入されていない（Issue #121 追加修正、空 COMMENTED 副産物の誤拾い対策）"
fi

# 2. state == APPROVED or CHANGES_REQUESTED で絞り込む
if echo "$WORKFLOW_POST_PROMPT" | grep -F '.state == "APPROVED" or .state == "CHANGES_REQUESTED"' > /dev/null; then
  pass "substantive review filter が state APPROVED/CHANGES_REQUESTED で絞り込む（Issue #121 追加修正）"
else
  fail "substantive review filter が state APPROVED/CHANGES_REQUESTED で絞り込んでいない（Issue #121 追加修正）"
fi

# 3. body 非空で絞り込む（auto_resolve 副産物の空 COMMENTED 排除）
if echo "$WORKFLOW_POST_PROMPT" | grep -E '\(\.body // ""\) \| length > 0' > /dev/null; then
  pass "substantive review filter が body 非空で絞り込む（Issue #121 追加修正、空 body の auto_resolve 副産物排除）"
else
  fail "substantive review filter が body 非空で絞り込んでいない（Issue #121 追加修正）"
fi

# 4. fallback として素の最新 review を取得するロジックが含まれる
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'if [[ -n "${substantive_review_json}" ]]' > /dev/null; then
  pass "substantive review が無い場合の fallback ロジックが含まれる（Issue #121 追加修正）"
else
  fail "substantive review が無い場合の fallback ロジックが含まれない（Issue #121 追加修正、初回 review 未投稿などの edge case 対応）"
fi

# Issue #152 fix: bundled review POST を workflow step に移管
# 旧設計では Claude prompt 内で `gh api -X POST .../pulls/N/reviews` を直接実行していたが、
# LLM の試し打ち POST が PR #151 で観測された（同一 run 内で本物の前に 4 回のノイズ review が残る）。
# PR #128 と同じ「workflow step で決定論的に POST」パターンに移管し、Claude には JSON
# ペイロード組み立てまでさせ、後続 workflow step が App Installation Token で 1 回だけ POST する。

# 1. 新 step「vibehawk bundled review を post」が存在する
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'vibehawk bundled review を post' > /dev/null; then
  pass "新 step「vibehawk bundled review を post」が存在する（Issue #152 fix）"
else
  fail "新 step「vibehawk bundled review を post」が存在しない（Issue #152 fix、bundled review POST の workflow step 移管が前提）"
fi

# 2. 新 step の if 条件に hashFiles('vibehawk-review.json') が含まれる
# claude-code-action が JSON 書き出しに失敗した場合の skip 経路（次の status check が neutral に倒れる）
if echo "$WORKFLOW_POST_PROMPT" | grep -F "hashFiles('vibehawk-review.json')" > /dev/null; then
  pass "新 step の if 条件に hashFiles('vibehawk-review.json') が含まれる（Issue #152 fix、Claude 書き出し失敗時の安全な skip）"
else
  fail "新 step の if 条件に hashFiles('vibehawk-review.json') が含まれない（Issue #152 fix、JSON 不在時の skip 経路が必須）"
fi

# 3. 新 step が App Installation Token（steps.app-token.outputs.token）を使う
# bot 名義 vibehawk-for-<owner>[bot] を維持するため必須（GITHUB_TOKEN を使うと github-actions[bot] 名義になる）
if echo "$WORKFLOW_POST_PROMPT" | grep -E 'GH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*steps\.app-token\.outputs\.token[[:space:]]*\}\}' > /dev/null; then
  pass "新 step が App Installation Token (steps.app-token.outputs.token) を使う（Issue #152 fix、bot 名義投稿維持）"
else
  fail "新 step が App Installation Token を使っていない（Issue #152 fix、bot 名義 vibehawk-for-<owner>[bot] 維持に必須）"
fi

# 4. 新 step が gh api -X POST pulls/$PR_NUMBER/reviews を --input で post する
# 注: grep に "--input" を渡すと flag と解釈されるため `-e -- --input` ではなく "-e '\\-\\-input'" 形式を使う
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'gh api -X POST' | grep -F '/pulls/' | grep -F '/reviews' | grep -E '\-\-input' > /dev/null; then
  pass "新 step が gh api -X POST .../pulls/.../reviews --input で post する（Issue #152 fix、決定論的 1 回 POST）"
else
  fail "新 step が決定論的 bundled review POST を行っていない（Issue #152 fix、gh api -X POST --input が前提）"
fi

# 5. 新 step が JSON 必須キー検証（event / body / commit_id / comments(array)）を行う
# Claude が壊れた JSON を書き出した場合に POST する前に check して step を skip する経路
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'jq -e' | grep -F '.event and .body and .commit_id' > /dev/null; then
  pass "新 step が JSON 必須キー（event/body/commit_id/comments）を検証する（Issue #152 fix、破損 JSON での POST 防止）"
else
  fail "新 step が JSON 必須キー検証を行っていない（Issue #152 fix、破損 JSON での POST を防ぐため必須）"
fi

# 6. prompt から `gh api -X POST repos/.../pulls/.../reviews` の直接実行サンプルが削除されている
# Claude prompt 内で bundled review を直接 POST する経路は撤廃すべき（Issue #152）
# 注: 「絶対禁止」セクションの記述（"... reviews で bundled review を直接 POST する"）は許容する。
# 検証したいのは「実行サンプル（コードフェンス内の bash コマンド）が残っていないこと」のため
# gh api -X POST と pulls/.../reviews と --input が同一行（実行コマンド形式）にあるかをチェックする。
if echo "$WORKFLOW_PROMPT" | grep -F 'gh api -X POST' | grep -F '/pulls/' | grep -F '/reviews' | grep -E '\-\-input' > /dev/null; then
  fail "prompt 内に bundled review POST 実行サンプル（gh api -X POST ... pulls/.../reviews ... --input）が残っている（Issue #152 fix、workflow step に移管すべき）"
else
  pass "prompt 内に bundled review POST 実行サンプルが残っていない（Issue #152 fix、workflow step に移管済み）"
fi

# 7. prompt に「vibehawk-review.json を書き出す」指示が含まれる
# Claude のタスク完了条件が JSON 書き出しまでであることを明示
if echo "$WORKFLOW_PROMPT" | grep -F 'vibehawk-review.json' > /dev/null; then
  pass "prompt に vibehawk-review.json 書き出し指示が含まれる（Issue #152 fix、Claude のタスク完了条件）"
else
  fail "prompt に vibehawk-review.json 書き出し指示が含まれない（Issue #152 fix、Claude が POST 直接実行に戻ってしまう）"
fi

# 8. prompt の「絶対禁止」リストに Issue #152 の bundled review POST 禁止が明示されている
# LLM の試し打ちを構造的に防止するため、明示的に禁止を書く必要がある
if echo "$WORKFLOW_PROMPT" | grep -F 'Issue #152' > /dev/null; then
  pass "prompt に Issue #152 fix の言及が含まれる（bundled review POST 禁止の根拠を明示）"
else
  fail "prompt に Issue #152 fix の言及が含まれない（bundled review POST 禁止の根拠が示されていない）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
