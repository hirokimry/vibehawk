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

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
