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

WORKFLOW_RAW="${REPO_ROOT}/templates/.github/workflows/vibehawk-review.yml"

echo "=== templates/.github/workflows/vibehawk-review.yml 検証 ==="

# ファイル存在（前提: 不在なら全後続テスト無意味）
if [[ -f "$WORKFLOW_RAW" ]]; then
  pass "templates/.github/workflows/vibehawk-review.yml が存在する"
else
  fail "templates/.github/workflows/vibehawk-review.yml が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# Issue #176: ラッパー展開
# `run: bash scripts/ci/vibehawk-review/<name>.sh` のような wrapper-call 行は、
# 当該 .sh の中身を本来の `run: |` ブロックの位置に inline 展開した「擬似 yaml」を
# 作って、後続の `awk '/id: .../, /^[[:space:]]+- name:/'` ベースのテストが
# step 内容を見られるようにする（Issue #176 の挙動不変リファクタの単体テスト維持）。
# 展開は副作用のない tempfile に書き出し、$WORKFLOW 変数を切り替えるだけで済むため
# 後続の awk / grep ロジックは無改変で動く。
WORKFLOW_EXPANDED_TMP="$(mktemp)"
trap 'rm -f "$WORKFLOW_EXPANDED_TMP"' EXIT
python3 - "$WORKFLOW_RAW" "$REPO_ROOT" > "$WORKFLOW_EXPANDED_TMP" <<'PYEOF'
import sys, os, re

# Windows runner ではロケールが CP1252 で、open() / sys.stdout のデフォルト encoding が
# CP1252 となるため、UTF-8 で書かれた yml / .sh（日本語コメント含む）を読み書きすると
# UnicodeDecodeError になる。encoding を明示して runner OS 非依存にする。
sys.stdout.reconfigure(encoding='utf-8')

src_path = sys.argv[1]
repo_root = sys.argv[2]
with open(src_path, encoding='utf-8') as f:
    yaml_text = f.read()

# ラッパー呼び出し行（例: `        run: bash scripts/ci/vibehawk-review/check-secrets.sh`）を
# 当該 .sh の中身 inline 展開した `run: |` ブロックに置き換える。インデントは run: 行と同じ
# leading whitespace の +2 スペース（GitHub Actions の標準）に揃える。
pattern = re.compile(r'^(\s+)run:\s+bash\s+"\$\{VIBEHAWK_RUNTIME\}/(scripts/ci/\S+\.sh)"\s*$', re.MULTILINE)

def replace(match):
    indent = match.group(1)
    rel = match.group(2).strip()
    abs_path = os.path.join(repo_root, rel)
    # 参照先 .sh が無いケースは「壊れた参照」として即エラー終了する
    # （未存在時に元の run: 行を返して続行すると、後段テストの fail 原因が
    # 「シェルが空展開された」のか「ファイルが本当に無い」のか切り分け不能になる）
    if not os.path.isfile(abs_path):
        sys.stderr.write(f"::error::ラッパー参照先 .sh が存在しない: {abs_path}\n")
        sys.exit(1)
    with open(abs_path, encoding='utf-8') as g:
        content = g.read()
    indented = ''.join(f"{indent}  {line}" for line in content.splitlines(keepends=True))
    if not indented.endswith('\n'):
        indented += '\n'
    return f"{indent}run: |\n{indented.rstrip(chr(10))}"

sys.stdout.write(pattern.sub(replace, yaml_text))
PYEOF

WORKFLOW="$WORKFLOW_EXPANDED_TMP"

# プロンプト本文は .github/prompts/vibehawk-review.md に切り出されたため（PR #235、21000 chars 制限回避）。
PROMPT_MD="${REPO_ROOT}/.github/prompts/vibehawk-review.md"

# コメント行を除外したワークフロー本文（行頭 # を除外）。
# 重要: prompt md 連結の **前** に awk 除外する。md は markdown 見出し `## ...` を含み、
# `!/^[[:space:]]*#/` で除外されてしまうため。md はコメント除外の対象外として後で丸ごと連結する。
WORKFLOW_BODY="$(awk '!/^[[:space:]]*#/' "$WORKFLOW")"

# WORKFLOW_BODY（コメント除外済み yaml）に prompt md を連結し、prompt 規約検証を切り出し後も維持する。
if [[ -f "$PROMPT_MD" ]]; then
  WORKFLOW_BODY="${WORKFLOW_BODY}"$'\n'"$(cat "$PROMPT_MD")"
  # `$WORKFLOW`（ファイル）を直接 grep する assertion 用に、ファイル自体にも md を連結する。
  # WORKFLOW_BODY の awk 除外は連結前に済んでいるため二重連結にならない。
  cat "$PROMPT_MD" >> "$WORKFLOW_EXPANDED_TMP"
fi

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

(
  export PATH="$MOCK_DIR:$PATH"
  export REPO="hirokimry/vibehawk"
  export PR_NUMBER="999"
  export EVENT="REQUEST_CHANGES"
  export REVIEW_BODY="test summary body"
  export HEAD_SHA="deadbeef1234567890abcdef1234567890abcdef"

  cat > "$MOCK_DIR/comments_array.json" <<'JSON'
[
  {"path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "🟠 **Major**: test"}
]
JSON

  jq -n \
    --arg event "$EVENT" \
    --arg body "$REVIEW_BODY" \
    --arg commit_id "$HEAD_SHA" \
    --slurpfile comments "$MOCK_DIR/comments_array.json" \
    '{event: $event, body: $body, commit_id: $commit_id, comments: $comments[0]}' \
    | gh api -X POST "repos/$REPO/pulls/$PR_NUMBER/reviews" --input -
)

post_count="$(grep -cE -- '-X POST repos/[^ ]+/pulls/[0-9]+/reviews' "$MOCK_DIR/gh_calls.log" || true)"
if [[ "$post_count" -eq 1 ]]; then
  pass "bundled POST /pulls/N/reviews がランタイムでちょうど 1 回呼ばれる（Issue #121）"
else
  fail "bundled POST /pulls/N/reviews の呼出回数が想定外: ${post_count} 回（Issue #121、期待: 1）"
fi

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

# Issue #10 / #172: .vibehawk.yaml 単独受付（.coderabbit.yaml fallback は #172 で撤廃）
if grep -F '.vibehawk.yaml' "$WORKFLOW" > /dev/null; then
  pass ".vibehawk.yaml が参照される（Issue #10）"
else
  fail ".vibehawk.yaml の参照が不足（Issue #10 未実装）"
fi

# Issue #172: .coderabbit.yaml の読込経路（ファイル存在 check / config_file 代入）が撤廃されている
# （Issue 履歴を残す情報コメントとしての文字列言及は許容する）
if ! grep -F '[[ -f ".coderabbit.yaml" ]]' "$WORKFLOW" > /dev/null && \
   ! grep -F 'config_file=".coderabbit.yaml"' "$WORKFLOW" > /dev/null; then
  pass ".coderabbit.yaml の読込経路が存在しない（Issue #172 fallback 撤廃）"
else
  fail ".coderabbit.yaml の読込経路が残っている（Issue #172 で撤廃済のはず）"
fi

# Issue #172: source_label の値域は vibehawk / default の 2 値のみ（coderabbit は撤廃）
if grep -F 'source_label="vibehawk"' "$WORKFLOW" > /dev/null && \
   grep -F 'source_label="default"' "$WORKFLOW" > /dev/null; then
  pass "source_label の vibehawk / default 2 値が定義されている（Issue #172）"
else
  fail "source_label の値域定義が不足（Issue #172、vibehawk / default の両方が必須）"
fi

if ! grep -F 'source_label="coderabbit"' "$WORKFLOW" > /dev/null; then
  pass "source_label=\"coderabbit\" の出力経路が存在しない（Issue #172）"
else
  fail "source_label=\"coderabbit\" の出力経路が残っている（Issue #172 で撤廃済のはず）"
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

# プロンプト本文は .github/prompts/vibehawk-review.md に切り出されたため（PR #235、21000 chars 制限回避）、
# prompt セクション検証は md ファイルを直接読む。旧 `prompt: |` block awk 抽出は切り出しで空になる。
if [[ -f "$PROMPT_MD" ]]; then
  WORKFLOW_PROMPT="$(cat "$PROMPT_MD")"
else
  # 後方互換: md が無ければ旧来の `prompt: |` block 抽出にフォールバック
  WORKFLOW_PROMPT="$(awk '/prompt:[[:space:]]*\|/{flag=1; next} /^[[:space:]]+claude_args:/{flag=0} flag' "$WORKFLOW")"
fi
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

# Issue #164 fix: ファイル書き出し依存を `--json-schema` + `outputs.structured_output` 経路に置換
# 旧設計（Issue #152）では Claude が $GITHUB_WORKSPACE/vibehawk-review.json にファイル書き出しし、
# 本 step が hashFiles で検出して読み込んでいた。指摘 0 件 PR で Claude が書き出しに失敗する事象
# （PR #159 で実証 = Issue #164）が prompt 強化（Issue #162 / PR #163）では再発したため、ファイル
# 書き出し経路を構造的に廃止し、claude-code-action の公式 outputs（schema validated）から受け取る。

# 1. 新 step「vibehawk bundled review を post」が存在する（Issue #152 で導入、Issue #164 で入力経路変更）
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'vibehawk bundled review を post' > /dev/null; then
  pass "新 step「vibehawk bundled review を post」が存在する（Issue #152 / #164 fix）"
else
  fail "新 step「vibehawk bundled review を post」が存在しない（Issue #152 / #164 fix、bundled review POST の workflow step 移管が前提）"
fi

# 2. 新 step の if 条件から hashFiles('vibehawk-review.json') が **撤廃** されている（Issue #164 fix）
# 旧設計では Claude のファイル書き出し成功を hashFiles で検出していたが、Issue #164 fix で
# `steps.claude_review.outputs.structured_output != ''` 経路に置換される。
if echo "$WORKFLOW_POST_PROMPT" | grep -F "hashFiles('vibehawk-review.json')" > /dev/null; then
  fail "新 step の if 条件に hashFiles('vibehawk-review.json') が残置されている（Issue #164 fix、撤廃すべき。ファイル書き出し依存は構造的廃止）"
else
  pass "新 step の if 条件から hashFiles('vibehawk-review.json') が撤廃されている（Issue #164 fix、ファイル書き出し依存の構造的廃止）"
fi

# 2-bis. 新 step の if 条件に steps.claude_review.outputs.structured_output != '' が含まれる（Issue #164 fix）
if echo "$WORKFLOW_POST_PROMPT" | grep -F "steps.claude_review.outputs.structured_output != ''" > /dev/null; then
  pass "新 step の if 条件に steps.claude_review.outputs.structured_output != '' が含まれる（Issue #164 fix、schema validated 応答経路）"
else
  fail "新 step の if 条件に steps.claude_review.outputs.structured_output != '' が含まれない（Issue #164 fix、Claude 応答空時の安全な skip 経路）"
fi

# 2-ter. 新 step の env に STRUCTURED_OUTPUT が含まれる（Issue #164 fix）
if echo "$WORKFLOW_POST_PROMPT" | grep -E 'STRUCTURED_OUTPUT:[[:space:]]*\$\{\{[[:space:]]*steps\.claude_review\.outputs\.structured_output[[:space:]]*\}\}' > /dev/null; then
  pass "新 step の env に STRUCTURED_OUTPUT が steps.claude_review.outputs.structured_output から渡されている（Issue #164 fix）"
else
  fail "新 step の env に STRUCTURED_OUTPUT が渡されていない（Issue #164 fix、run ブロックで参照するため env 受け渡しが必須）"
fi

# 2-quater. 新 step が ${RUNNER_TEMP} 経由でペイロードをファイル化する（Issue #164 fix）
# $GITHUB_WORKSPACE（actions/checkout 管理領域）から退避するため
if echo "$WORKFLOW_POST_PROMPT" | grep -F '${RUNNER_TEMP}/vibehawk-review.json' > /dev/null \
   && echo "$WORKFLOW_POST_PROMPT" | grep -F "printf '%s' \"\$STRUCTURED_OUTPUT\"" > /dev/null; then
  pass "新 step が \${RUNNER_TEMP} に printf '%s' \"\$STRUCTURED_OUTPUT\" で書き出す（Issue #164 fix、決定論的書き出し + 特殊文字保護）"
else
  fail "新 step が \${RUNNER_TEMP} 経由 printf 書き出しを行っていない（Issue #164 fix、echo 系の特殊文字破壊を回避するため printf '%s' が必須）"
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
# claude-code-action 内 schema validation の二重防御として workflow step 側も jq 契約検証する
# PR #153 CodeRabbit 追加 Major 指摘対応で検証を強化済み:
# event 値が APPROVE/REQUEST_CHANGES/COMMENT のいずれかに限定、body/commit_id 非空、
# comments[] の path/body 非空、line/side/start_line/start_side の型整合を jq で検証する。
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'jq -e' > /dev/null \
   && echo "$WORKFLOW_POST_PROMPT" | grep -F '.event == "APPROVE"' > /dev/null \
   && echo "$WORKFLOW_POST_PROMPT" | grep -F '.event == "REQUEST_CHANGES"' > /dev/null \
   && echo "$WORKFLOW_POST_PROMPT" | grep -F '.event == "COMMENT"' > /dev/null \
   && echo "$WORKFLOW_POST_PROMPT" | grep -F '(.comments | type == "array")' > /dev/null; then
  pass "新 step が GitHub Reviews API 契約に厳格な JSON 検証を行う（event 値限定 + body/commit_id 非空 + comments[] shape、Issue #152 fix + PR #153 強化 + Issue #164 fix で schema validation の二重防御）"
else
  fail "新 step の JSON 検証が GitHub Reviews API 契約に従っていない（event 値の APPROVE/REQUEST_CHANGES/COMMENT 限定 + comments[] shape 検証が必須、PR #153 CodeRabbit Major 指摘）"
fi

# 5-bis. 新 step の warning メッセージから "vibehawk-review.json" の表記が撤去されている（Issue #164 fix）
# 旧 warning は "vibehawk-review.json の検証に失敗" と書かれており、ファイル書き出し依存の誤誘導を招く。
# Issue #164 fix で「outputs.structured_output の jq 契約検証に失敗」に書き換える。
# 注意: warning メッセージ行（echo "::warning::..."）に限定して検証する（コメント行や run の他行は許容）。
if echo "$WORKFLOW_POST_PROMPT" | grep -F '::warning::vibehawk' | grep -F 'vibehawk-review.json の検証に失敗' > /dev/null; then
  fail "新 step の warning メッセージに旧表記 'vibehawk-review.json の検証に失敗' が残っている（Issue #164 fix、利用者が ファイル書き出し失敗 と誤解する誘導を招く）"
else
  pass "新 step の warning メッセージから 'vibehawk-review.json の検証に失敗' 表記が撤去されている（Issue #164 fix、誤誘導防止）"
fi

# 5-ter. 新 step の warning メッセージに新表記 "outputs.structured_output の jq 契約検証に失敗" が含まれる（Issue #164 fix）
if echo "$WORKFLOW_POST_PROMPT" | grep -F '::warning::vibehawk' | grep -F 'outputs.structured_output の jq 契約検証に失敗' > /dev/null; then
  pass "新 step の warning メッセージが 'outputs.structured_output の jq 契約検証に失敗' に書き換えられている（Issue #164 fix、正しい根拠表記）"
else
  fail "新 step の warning メッセージに新表記 'outputs.structured_output の jq 契約検証に失敗' が含まれない（Issue #164 fix）"
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

# 7. prompt に「schema 適合 JSON を最終 assistant message として返す」指示が含まれる（Issue #164 fix）
# 旧テスト（vibehawk-review.json 書き出し指示が含まれる）を **反転**：書き出し指示は撤廃済みで、
# 新タスク完了条件は「最終 assistant message として schema 適合 JSON を返す」こと。
if echo "$WORKFLOW_PROMPT" | grep -F 'schema 適合 JSON' > /dev/null \
   && echo "$WORKFLOW_PROMPT" | grep -F '最終 assistant message' > /dev/null; then
  pass "prompt に「schema 適合 JSON を最終 assistant message として返す」指示が含まれる（Issue #164 fix、新タスク完了条件）"
else
  fail "prompt に schema 適合 JSON / 最終 assistant message の指示が含まれない（Issue #164 fix、Claude が旧経路に戻ってしまう）"
fi

# 7-bis. prompt の「絶対禁止」セクションでファイル書き出し全般を禁止していることを検証（Issue #164 fix）
# 旧設計では vibehawk-review.json の書き出しがタスク完了条件だったが、Issue #164 fix で「絶対禁止」に移行
if echo "$WORKFLOW_PROMPT" | grep -F 'ファイル書き出し' > /dev/null \
   && echo "$WORKFLOW_PROMPT" | grep -F 'Issue #164 fix' > /dev/null; then
  pass "prompt の絶対禁止にファイル書き出し全般が含まれ Issue #164 fix の根拠が明示されている（schema 外経路の構造的廃止）"
else
  fail "prompt の絶対禁止にファイル書き出し全般 / Issue #164 fix の言及が含まれない（Claude が旧経路に戻ってしまう）"
fi

# 8. prompt の「絶対禁止」リストに Issue #152 の bundled review POST 禁止と Issue #164 fix の根拠が明示されている
# LLM の試し打ちを構造的に防止するため、明示的に禁止を書く必要がある（Issue #152 言及は歴史的経緯として維持）
if echo "$WORKFLOW_PROMPT" | grep -F 'Issue #152' > /dev/null; then
  pass "prompt に Issue #152 fix の言及が含まれる（bundled review POST 禁止の根拠を明示）"
else
  fail "prompt に Issue #152 fix の言及が含まれない（bundled review POST 禁止の根拠が示されていない）"
fi

# 8-bis. claude-code-action step に id: claude_review が宣言されている（Issue #164 fix）
# 後続の bundled POST step が steps.claude_review.outputs.structured_output を参照するために必須
if grep -E "^[[:space:]]+id:[[:space:]]*claude_review[[:space:]]*\$" "$WORKFLOW" > /dev/null; then
  pass "claude-code-action step に id: claude_review が宣言されている（Issue #164 fix、outputs 参照用）"
else
  fail "claude-code-action step に id: claude_review が宣言されていない（Issue #164 fix、後続 step の outputs 参照に必須）"
fi

# 8-ter. claude_args に --json-schema が含まれる（Issue #164 fix）
# Claude の最終応答を JSON schema で validate するための公式機能
if echo "$WORKFLOW_POST_PROMPT" | grep -F -- '--json-schema' > /dev/null; then
  pass "claude_args に --json-schema が含まれる（Issue #164 fix、schema validated 応答の公式機能）"
else
  fail "claude_args に --json-schema が含まれない（Issue #164 fix、schema 強制が無いと Claude 応答の構造が保証されない）"
fi

# 8-quater. --json-schema に APPROVE/REQUEST_CHANGES/COMMENT の 3 値 enum が含まれる（Issue #164 fix）
# event の値域を機械的に強制し、REQUEST_CHANGES / COMMENT ケースの存続を schema レベルで保証する
if echo "$WORKFLOW_POST_PROMPT" | grep -F '"enum":["APPROVE","REQUEST_CHANGES","COMMENT"]' > /dev/null; then
  pass "--json-schema に event の enum [APPROVE,REQUEST_CHANGES,COMMENT] が含まれる（Issue #164 fix、event 値域の機械的強制 + 全 3 ケース存続保証）"
else
  fail "--json-schema に event の enum [APPROVE,REQUEST_CHANGES,COMMENT] が含まれない（Issue #164 fix、event 値域の機械的強制 + REQUEST_CHANGES/COMMENT 存続保証に必須）"
fi

# Issue #65: paths-ignore による推奨ノイズ抑制設定
# templates/.github/workflows/vibehawk-review.yml に推奨 paths-ignore を同梱し、
# ドキュメントのみ・lock ファイルのみ・dependabot 自動更新のような PR では
# vibehawk auto-review を GitHub Actions レベルでスキップする（API コスト 0）。
# 利用者は本リストを自由に編集・追加・削除できる（コメントで明示）。

# 1. paths-ignore: ブロックが存在する（on.pull_request 直下）
# yq を使わず grep ベースで実装（CI 依存ゼロを優先、shell.md YAML パースの方針に従い
# 固定行数 -A ではなく "^    paths-ignore:" を含む行の存在チェックのみとする）
if grep -E "^[[:space:]]+paths-ignore:" "$WORKFLOW" > /dev/null; then
  pass "paths-ignore: ブロックが存在する（Issue #65 推奨ノイズ抑制設定）"
else
  fail "paths-ignore: ブロックが存在しない（Issue #65、推奨ノイズ抑制設定の前提）"
fi

# 2. 推奨 5 パターン全てが含まれる（Issue #65 → Issue #160 で `**/*.md` / `CHANGELOG*` を撤回）
declare -a required_path_patterns=(
  "'.github/dependabot.yml'"
  "'package-lock.json'"
  "'yarn.lock'"
  "'pnpm-lock.yaml'"
  "'bun.lockb'"
)
for pattern in "${required_path_patterns[@]}"; do
  if grep -F "$pattern" "$WORKFLOW" > /dev/null; then
    pass "paths-ignore に推奨パターン $pattern が含まれる（Issue #65）"
  else
    fail "paths-ignore に推奨パターン $pattern が含まれない（Issue #65）"
  fi
done

# 3. 利用者が編集可能であることを示すコメントが含まれる
# 受け入れ条件 #2「利用者が簡単に追加・削除できる位置に明確なコメント記載」を機械検証
if grep -F "編集" "$WORKFLOW" > /dev/null && \
   grep -F "Issue #65" "$WORKFLOW" > /dev/null; then
  pass "paths-ignore に利用者向け編集可能コメントが含まれる（Issue #65 受け入れ条件 #2）"
else
  fail "paths-ignore に利用者向け編集可能コメントが含まれない（Issue #65 受け入れ条件 #2）"
fi

# Issue #166: event 判定ロジックを Claude prompt から workflow step に移管
# 旧設計（Issue #121）では Claude が prompt 内で severity 分布カウント + reviewThreads
# の unresolved 数取得 + 判定ルールを実行して JSON の event フィールドに書き込んでいた。
# これは Claude の確率的応答に依存しており、判定ミス・形式破りの余地が残っていた。
# Issue #166 で同じ判定ロジックを workflow step (decide_event) で決定論的に再実装し、
# bundled POST step が decide_event の出力で Claude の event フィールドを上書きする。

# 1. 新 step「vibehawk event を決定」が存在する（Issue #166）
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'vibehawk event を決定' > /dev/null; then
  pass "新 step「vibehawk event を決定」が存在する（Issue #166）"
else
  fail "新 step「vibehawk event を決定」が存在しない（Issue #166、event 判定の workflow step 移管が前提）"
fi

# 2. decide_event step に id: decide_event が宣言されている（後続 bundled POST step が steps.decide_event.outputs.decided_event を参照するために必須）
if grep -E "^[[:space:]]+id:[[:space:]]*decide_event[[:space:]]*\$" "$WORKFLOW" > /dev/null; then
  pass "decide_event step に id: decide_event が宣言されている（Issue #166、outputs 参照用）"
else
  fail "decide_event step に id: decide_event が宣言されていない（Issue #166、bundled POST step の outputs 参照に必須）"
fi

# 3. decide_event step が claude-code-action と bundled POST の間に配置されている
# 順序: claude_review → decide_event → bundled POST
# step header（`- name: ...`）の行番号で配置順を比較する。
# 注意: prompt 本文内にも step 名のテキスト言及があるため、`grep -n '- name: vibehawk bundled review を post'`
# のように step header の YAML 構造を含む完全形で検索する必要がある。
claude_review_line=$(grep -n 'id: claude_review' "$WORKFLOW" | head -1 | cut -d: -f1)
decide_event_line=$(grep -n '^[[:space:]]\+id:[[:space:]]*decide_event[[:space:]]*$' "$WORKFLOW" | head -1 | cut -d: -f1)
bundled_post_line=$(grep -n '^[[:space:]]\+- name: vibehawk bundled review を post' "$WORKFLOW" | head -1 | cut -d: -f1)
if [[ -n "$claude_review_line" && -n "$decide_event_line" && -n "$bundled_post_line" ]] \
   && [[ "$claude_review_line" -lt "$decide_event_line" ]] \
   && [[ "$decide_event_line" -lt "$bundled_post_line" ]]; then
  pass "decide_event step が claude_review と bundled POST の間に配置されている（Issue #166、Claude 応答 → 判定 → POST の順序）"
else
  fail "decide_event step の配置順が想定外（claude_review=${claude_review_line:-N/A} / decide_event=${decide_event_line:-N/A} / bundled_post=${bundled_post_line:-N/A}、Issue #166）"
fi

# 4. decide_event step が check_secrets ガードと structured_output 非空ガードを継承
# 後続の bundled POST と同じ if 条件を使うことで、Claude 応答が無い場合に skip する
if awk '/id:[[:space:]]*decide_event/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F "steps.check_secrets.outputs.ready == 'true'" > /dev/null \
   && awk '/id:[[:space:]]*decide_event/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F "steps.claude_review.outputs.structured_output != ''" > /dev/null; then
  pass "decide_event step が check_secrets.ready + structured_output 非空の二重ガードを継承（Issue #166、Claude 応答無し時の安全 skip）"
else
  fail "decide_event step のガード条件が想定外（Issue #166、check_secrets.ready + structured_output != '' の両方が必須）"
fi

# 5. decide_event step が GraphQL reviewThreads クエリを呼ぶ
# auto_resolve mutation 後の最新 unresolved 状態を取得するため必須
if awk '/id:[[:space:]]*decide_event/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F 'gh api graphql' > /dev/null \
   && awk '/id:[[:space:]]*decide_event/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F 'reviewThreads' > /dev/null \
   && awk '/id:[[:space:]]*decide_event/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F 'isResolved' > /dev/null; then
  pass "decide_event step が gh api graphql で reviewThreads.isResolved を取得（Issue #166）"
else
  fail "decide_event step が GraphQL reviewThreads クエリを呼んでいない（Issue #166、unresolved 数の決定論的取得に必須）"
fi

# 6. decide_event step が jq で comments[] の actionable 件数を集計（Issue #171: severity 不問・件数主軸 / Issue #270: 🧹 Nitpick 除外）
# 旧実装（Issue #166）では body 冒頭絵文字（🔴 / 🟠）で Critical/Major のみカウントしていたが、
# Issue #171 で severity 不問の件数判定に変更し、Issue #270 で 🧹 Nitpick（非ブロッキング）を除外する
# `select(.category != "🧹 Nitpick")` 形式になった。startswith() による severity フィルタは含まれない。
if awk '/id:[[:space:]]*decide_event/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F 'select(.category != "🧹 Nitpick")' > /dev/null; then
  pass "decide_event step が jq で actionable 件数を集計（🧹 Nitpick 除外、Issue #171/#270）"
else
  fail "decide_event step が actionable 件数集計（🧹 Nitpick 除外）を行っていない（Issue #171/#270 に必須）"
fi

# 6-bis. Issue #171 で旧 startswith("🔴") / startswith("🟠") の severity フィルタが撤去されている
# severity 別カウントは判定に使わない設計に変更（severity 不問・件数主軸）
if awk '/id:[[:space:]]*decide_event/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F 'startswith("🔴")' > /dev/null \
   || awk '/id:[[:space:]]*decide_event/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F 'startswith("🟠")' > /dev/null; then
  fail "decide_event step に旧 severity フィルタ（startswith(\"🔴\") / startswith(\"🟠\")）が残っている（Issue #171、severity 不問・件数主軸に変更したため撤去すべき）"
else
  pass "decide_event step から旧 severity フィルタが撤去されている（Issue #171）"
fi

# 7. decide_event step が判定ルール 3 段階を実装（Issue #171: severity 不問・件数主軸）
# - unresolved >= 1 → REQUEST_CHANGES（最優先）
# - 新規 inline 指摘の総件数 >= 1 → REQUEST_CHANGES（severity 不問、Issue #171）
# - それ以外 → APPROVE
decide_block="$(awk '/id:[[:space:]]*decide_event/,/^[[:space:]]+- name:/' "$WORKFLOW")"
if echo "$decide_block" | grep -F 'unresolved_count' > /dev/null \
   && echo "$decide_block" | grep -F 'new_comments_count' > /dev/null \
   && echo "$decide_block" | grep -F 'decided_event="REQUEST_CHANGES"' > /dev/null \
   && echo "$decide_block" | grep -F 'decided_event="APPROVE"' > /dev/null; then
  pass "decide_event step が判定ルール 3 段階（unresolved + 新規総件数 → REQUEST_CHANGES / それ以外 → APPROVE）を実装（Issue #171: severity 不問・件数主軸）"
else
  fail "decide_event step の判定ルール実装が想定外（Issue #171、unresolved_count + new_comments_count + 3 段階判定が必須）"
fi

# 8. decide_event step が decided_event を GITHUB_OUTPUT に出力
if echo "$decide_block" | grep -E 'echo "decided_event=' > /dev/null; then
  pass "decide_event step が decided_event を GITHUB_OUTPUT に出力（Issue #166）"
else
  fail "decide_event step が decided_event を GITHUB_OUTPUT に出力していない（Issue #166、bundled POST step が参照できない）"
fi

# 9. bundled POST step の env に DECIDED_EVENT が含まれる
# steps.decide_event.outputs.decided_event を run ブロックで参照するため env 受け渡しが必須
# 注意: awk の範囲指定は step header（`- name: vibehawk bundled review を post`）から
# 次の step header（status check post）まで。prompt 本文内の text 言及を拾わないように
# `^[[:space:]]+- name:` の YAML 構造で範囲を切る。
bundled_block="$(awk '/^[[:space:]]+- name: vibehawk bundled review を post/,/^[[:space:]]+- name: vibehawk status check/' "$WORKFLOW")"
if echo "$bundled_block" | grep -E 'DECIDED_EVENT:[[:space:]]*\$\{\{[[:space:]]*steps\.decide_event\.outputs\.decided_event[[:space:]]*\}\}' > /dev/null; then
  pass "bundled POST step の env に DECIDED_EVENT が steps.decide_event.outputs.decided_event から渡されている（Issue #166）"
else
  fail "bundled POST step の env に DECIDED_EVENT が渡されていない（Issue #166、event 上書きに必須）"
fi

# 10. bundled POST step が jq で .event を $DECIDED_EVENT に上書きする
if echo "$bundled_block" | grep -F "jq --arg ev" > /dev/null \
   && echo "$bundled_block" | grep -F '.event = $ev' > /dev/null; then
  pass "bundled POST step が jq --arg ev '\$DECIDED_EVENT' '.event = \$ev' で event を上書きする（Issue #166）"
else
  fail "bundled POST step が jq による event 上書きを行っていない（Issue #166、決定論的 event 注入が前提）"
fi

# 11. bundled POST step が DECIDED_EVENT 空時の safe skip を実装
# `grep -F '-z'` は `-z` を flag と解釈するため `grep -F -- '-z'` で明示的に区切る
if echo "$bundled_block" | grep -F 'DECIDED_EVENT' | grep -F -- '-z' > /dev/null; then
  pass "bundled POST step が DECIDED_EVENT 空時の safe skip を実装（Issue #166）"
else
  fail "bundled POST step が DECIDED_EVENT 空時の safe skip を実装していない（Issue #166、decide_event 失敗時の防御）"
fi

# 12. Claude prompt から旧 event 判定セクション「## review event 決定（auto_resolve 後の unresolved 数 + 新規 inline の severity で）」が撤廃されている
# 旧見出しの正確な文字列が prompt 内に残っていないことを検証（書き換え後の Issue #166 見出しは「Issue #166 で workflow step に移管」を含む）
if echo "$WORKFLOW_PROMPT" | grep -F '## review event 決定（auto_resolve 後の unresolved 数 + 新規 inline の severity で）' > /dev/null; then
  fail "Claude prompt に旧 event 判定セクション見出しが残っている（Issue #166、workflow step 移管が前提）"
else
  pass "Claude prompt から旧 event 判定セクション見出しが撤廃されている（Issue #166）"
fi

# 13. Claude prompt に「event 判定は workflow step に移管」と Issue #166 の言及が含まれる
if echo "$WORKFLOW_PROMPT" | grep -F 'Issue #166' > /dev/null \
   && echo "$WORKFLOW_PROMPT" | grep -F 'workflow step' > /dev/null; then
  pass "Claude prompt に Issue #166 の言及と workflow step 移管の説明が含まれる（Issue #166）"
else
  fail "Claude prompt に Issue #166 / workflow step 移管の言及が含まれない（Issue #166、Claude が旧経路に戻ってしまう）"
fi

# 14. Claude prompt が event placeholder として COMMENT 固定を指示
if echo "$WORKFLOW_PROMPT" | grep -F 'placeholder' > /dev/null \
   && echo "$WORKFLOW_PROMPT" | grep -F 'COMMENT' > /dev/null; then
  pass "Claude prompt が event placeholder として COMMENT 固定を指示（Issue #166）"
else
  fail "Claude prompt が event placeholder 規約（COMMENT 固定）を指示していない（Issue #166）"
fi

# 15. Claude prompt のタスク完了条件から「event を決定」項目が削除されている
# 旧設計では「2. event を決定（APPROVE / REQUEST_CHANGES / COMMENT）」がタスク完了条件に含まれていたが、
# Issue #166 で workflow step に移管したため Claude のタスクからは外れる
if echo "$WORKFLOW_PROMPT" | grep -E '^[[:space:]]*2\. event を決定' > /dev/null; then
  fail "Claude prompt のタスク完了条件に旧「event を決定」項目が残っている（Issue #166、workflow step 移管で外すべき）"
else
  pass "Claude prompt のタスク完了条件から「event を決定」項目が削除されている（Issue #166）"
fi

# Issue #167: auto_resolve を Claude prompt から workflow step に移管
# 旧設計（Issue #9）では Claude が prompt 内で `gh api graphql resolveReviewThread`
# mutation を直接実行していた。Issue #164（structured_output 経路の確立） /
# Issue #166（event 判定の workflow 移管）に続く責務分離の完成形として workflow step
# に移管し、Claude は解決対象 thread の node_id を `resolved_thread_ids: [string]`
# 配列に列挙するだけになる。

# 1. --json-schema に resolved_thread_ids: array<string> が含まれる
if echo "$WORKFLOW_POST_PROMPT" | grep -F '"resolved_thread_ids":{"type":"array","items":{"type":"string"}}' > /dev/null; then
  pass "--json-schema に resolved_thread_ids (array of string) が含まれる（Issue #167、解決対象 thread_id を schema 経路で受け取る）"
else
  fail "--json-schema に resolved_thread_ids (array of string) が含まれない（Issue #167、workflow step 移管に必須）"
fi

# 2. 新 step「vibehawk auto_resolve」が存在する
if echo "$WORKFLOW_POST_PROMPT" | grep -F 'vibehawk auto_resolve' > /dev/null; then
  pass "新 step「vibehawk auto_resolve」が存在する（Issue #167）"
else
  fail "新 step「vibehawk auto_resolve」が存在しない（Issue #167、auto_resolve の workflow step 移管が前提）"
fi

# 3. auto_resolve step に id: auto_resolve が宣言されている
if grep -E "^[[:space:]]+id:[[:space:]]*auto_resolve[[:space:]]*\$" "$WORKFLOW" > /dev/null; then
  pass "auto_resolve step に id: auto_resolve が宣言されている（Issue #167）"
else
  fail "auto_resolve step に id: auto_resolve が宣言されていない（Issue #167）"
fi

# 4. auto_resolve step が claude_review と decide_event の間に配置されている
# 順序: claude_review → auto_resolve → decide_event → bundled POST → status check
# decide_event が GraphQL で unresolved 数を取得するため、auto_resolve mutation を
# decide_event の前に走らせる必要がある（旧 Claude prompt 内実装と同じ順序）。
auto_resolve_line=$(grep -n '^[[:space:]]\+id:[[:space:]]*auto_resolve[[:space:]]*$' "$WORKFLOW" | head -1 | cut -d: -f1)
if [[ -n "$claude_review_line" && -n "$auto_resolve_line" && -n "$decide_event_line" ]] \
   && [[ "$claude_review_line" -lt "$auto_resolve_line" ]] \
   && [[ "$auto_resolve_line" -lt "$decide_event_line" ]]; then
  pass "auto_resolve step が claude_review と decide_event の間に配置されている（Issue #167、Claude 応答 → mutation → event 判定の順序）"
else
  fail "auto_resolve step の配置順が想定外（claude_review=${claude_review_line:-N/A} / auto_resolve=${auto_resolve_line:-N/A} / decide_event=${decide_event_line:-N/A}、Issue #167）"
fi

# 5. auto_resolve step が check_secrets.ready + structured_output 非空の二重ガードを継承
if awk '/id:[[:space:]]*auto_resolve/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F "steps.check_secrets.outputs.ready == 'true'" > /dev/null \
   && awk '/id:[[:space:]]*auto_resolve/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F "steps.claude_review.outputs.structured_output != ''" > /dev/null; then
  pass "auto_resolve step が check_secrets.ready + structured_output 非空の二重ガードを継承（Issue #167）"
else
  fail "auto_resolve step のガード条件が想定外（Issue #167、check_secrets.ready + structured_output != '' の両方が必須）"
fi

# 6. auto_resolve step が gh api graphql + resolveReviewThread mutation を呼ぶ
# scripts/ci/vibehawk-review/auto-resolve.sh の中身が wrapper-call 展開されて含まれる
if awk '/id:[[:space:]]*auto_resolve/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F 'gh api graphql' > /dev/null \
   && awk '/id:[[:space:]]*auto_resolve/,/^[[:space:]]+- name:/' "$WORKFLOW" \
   | grep -F 'resolveReviewThread' > /dev/null; then
  pass "auto_resolve step が gh api graphql で resolveReviewThread mutation を呼ぶ（Issue #167、workflow step 内で副作用実行）"
else
  fail "auto_resolve step が gh api graphql resolveReviewThread mutation を呼んでいない（Issue #167、Claude prompt からの移管先）"
fi

# 7. auto_resolve step の env に STRUCTURED_OUTPUT / OWNER / REPO / PR_NUMBER が含まれる
auto_resolve_block="$(awk '/^[[:space:]]+- name: vibehawk auto_resolve/,/^[[:space:]]+- name: vibehawk event を決定/' "$WORKFLOW")"
if echo "$auto_resolve_block" | grep -E 'STRUCTURED_OUTPUT:[[:space:]]*\$\{\{[[:space:]]*steps\.claude_review\.outputs\.structured_output[[:space:]]*\}\}' > /dev/null \
   && echo "$auto_resolve_block" | grep -E 'OWNER:[[:space:]]*\$\{\{[[:space:]]*github\.repository_owner[[:space:]]*\}\}' > /dev/null \
   && echo "$auto_resolve_block" | grep -E 'REPO:[[:space:]]*\$\{\{[[:space:]]*github\.repository[[:space:]]*\}\}' > /dev/null \
   && echo "$auto_resolve_block" | grep -E 'PR_NUMBER:[[:space:]]*\$\{\{[[:space:]]*github\.event\.pull_request\.number[[:space:]]*\}\}' > /dev/null; then
  pass "auto_resolve step の env に STRUCTURED_OUTPUT / OWNER / REPO / PR_NUMBER が含まれる（Issue #167、二重防御の author 検証に必須）"
else
  fail "auto_resolve step の env が不足（Issue #167、STRUCTURED_OUTPUT / OWNER / REPO / PR_NUMBER の 4 つが必須）"
fi

# 8. auto_resolve step が App Installation Token (steps.app-token.outputs.token) を使う
# bot 名義 vibehawk-for-<owner>[bot] による mutation を実行するため必須
if echo "$auto_resolve_block" | grep -E 'GH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*steps\.app-token\.outputs\.token[[:space:]]*\}\}' > /dev/null; then
  pass "auto_resolve step が App Installation Token (steps.app-token.outputs.token) を使う（Issue #167、bot 名義 mutation 実行）"
else
  fail "auto_resolve step が App Installation Token を使っていない（Issue #167、vibehawk-for-<owner>[bot] 名義 mutation に必須）"
fi

# 9. Claude prompt から旧 mutation 実行サンプル (gh api graphql -f query='mutation { resolveReviewThread...) が削除されている
# 旧設計では prompt 内のコードフェンスで mutation 実行例が示されていたが、Issue #167 で削除する。
# 「絶対禁止」セクション内の「mutation を実行しない」記述は許可（実行コマンド形式ではない）。
# 検出は「mutation { resolveReviewThread」（コードフェンス内の実行サンプル形式）のパターン。
if echo "$WORKFLOW_PROMPT" | grep -F 'mutation { resolveReviewThread(input: { threadId' > /dev/null; then
  fail "Claude prompt に旧 mutation 実行サンプル (mutation { resolveReviewThread(input: { threadId) が残っている（Issue #167、workflow step 移管で削除すべき）"
else
  pass "Claude prompt から旧 mutation 実行サンプルが削除されている（Issue #167）"
fi

# 10. Claude prompt に resolved_thread_ids の言及と Issue #167 の言及が含まれる
if echo "$WORKFLOW_PROMPT" | grep -F 'resolved_thread_ids' > /dev/null \
   && echo "$WORKFLOW_PROMPT" | grep -F 'Issue #167' > /dev/null; then
  pass "Claude prompt に resolved_thread_ids / Issue #167 の言及が含まれる（Issue #167、workflow step 移管の根拠を明示）"
else
  fail "Claude prompt に resolved_thread_ids / Issue #167 の言及が含まれない（Issue #167、Claude が旧経路に戻ってしまう）"
fi

# 11. Claude prompt の「絶対禁止」リストに resolveReviewThread mutation の prompt 内実行禁止が含まれる
# LLM の試し打ちを構造的に防止するため、明示的に禁止を書く必要がある
if echo "$WORKFLOW_PROMPT" | grep -F '絶対禁止' > /dev/null \
   && echo "$WORKFLOW_PROMPT" | grep -F 'resolveReviewThread' > /dev/null \
   && echo "$WORKFLOW_PROMPT" | grep -F 'mutation' > /dev/null; then
  pass "Claude prompt の絶対禁止に resolveReviewThread mutation / gh api graphql mutation 系の prompt 内実行禁止が含まれる（Issue #167）"
else
  fail "Claude prompt の絶対禁止に resolveReviewThread mutation 禁止が含まれない（Issue #167、Claude の試し打ち防止に必須）"
fi

# 12. Claude prompt のタスク完了条件 1 が「resolved_thread_ids に列挙」に書き換えられている
# 旧: 「（INCREMENTAL_MODE=true なら）auto_resolve で旧指摘を resolved 化」
# 新: 「（INCREMENTAL_MODE=true なら）解決対象 thread の GraphQL node_id を `resolved_thread_ids` に列挙」
if echo "$WORKFLOW_PROMPT" | grep -E '^[[:space:]]*1\.' | grep -F 'auto_resolve で旧指摘を resolved 化' > /dev/null; then
  fail "Claude prompt のタスク完了条件 1 に旧記述「auto_resolve で旧指摘を resolved 化」が残っている（Issue #167、resolved_thread_ids 列挙に書き換えるべき）"
else
  pass "Claude prompt のタスク完了条件 1 から旧記述「auto_resolve で旧指摘を resolved 化」が削除されている（Issue #167）"
fi
if echo "$WORKFLOW_PROMPT" | grep -E '^[[:space:]]*1\.' | grep -F 'resolved_thread_ids' > /dev/null; then
  pass "Claude prompt のタスク完了条件 1 が「resolved_thread_ids に列挙」に書き換えられている（Issue #167）"
else
  fail "Claude prompt のタスク完了条件 1 に resolved_thread_ids の言及がない（Issue #167、新タスク完了条件として必須）"
fi

# 13. 旧「補足: 本 prompt で唯一許可される POST は resolveReviewThread mutation のみ」表記が削除されている
# Issue #167 で mutation も workflow step に移管したため、この補足記述は不要になる
if echo "$WORKFLOW_PROMPT" | grep -F '本 prompt で唯一許可される POST' > /dev/null; then
  fail "Claude prompt に旧記述「本 prompt で唯一許可される POST は resolveReviewThread mutation のみ」が残っている（Issue #167、mutation も移管したため削除すべき）"
else
  pass "Claude prompt から旧記述「本 prompt で唯一許可される POST は resolveReviewThread mutation のみ」が削除されている（Issue #167）"
fi

# === Issue #295（epic #289 子6）: 自動レビュー pause/resume/ignore の review.yml 統合 ===
echo "=== Issue #295: 自動レビュー状態 gate 検証 ==="

# 注: 本テストは run: bash scripts/ci/*.sh をスクリプト内容にインライン展開するため、
# 「bash <path>.sh」リテラルではなく id / gate 条件 / 展開後スクリプト内容文字列で検証する。
# CodeRabbit 指摘対応: グローバル grep ではなく該当 step ブロックにスコープして検証する。

# autoreview_state step ブロック（id: autoreview_state 〜 次 step id: prev_summary）に check ロジックがあるか
AUTOREVIEW_STEP_BLOCK="$(echo "$WORKFLOW_BODY" | awk '/id: autoreview_state/{f=1} f&&/id: prev_summary/{f=0} f{print}')"
if echo "$WORKFLOW_BODY" | grep -F 'id: autoreview_state' > /dev/null && \
   echo "$AUTOREVIEW_STEP_BLOCK" | grep -F 'vibehawk:autoreview=' > /dev/null; then
  pass "autoreview_state step が存在し、その step 内で vibehawk:autoreview マーカーを読む（Issue #295）"
else
  fail "autoreview_state step が存在しない / マーカー読取が step 内にない（Issue #295）"
fi

# claude_review step ブロックに state == 'active' gate があるか（step スコープ）
CLAUDE_REVIEW_BLOCK="$(echo "$WORKFLOW_BODY" | awk '/id: claude_review/{f=1} f{print} f&&/uses: anthropics/{f=0}')"
if echo "$CLAUDE_REVIEW_BLOCK" | grep -F "steps.autoreview_state.outputs.state == 'active'" > /dev/null; then
  pass "claude_review step が state == 'active' で gate される（Issue #295、paused/ignored で自動レビュー skip）"
else
  fail "claude_review step の active gate が存在しない（Issue #295）"
fi

# paused 専用 status step ブロックに state != 'active' gate + success post があるか（step スコープ）
PAUSED_STEP_BLOCK="$(echo "$WORKFLOW_BODY" | awk '/自動レビュー一時停止中/{f=1} f{print} f&&/AUTOREVIEW_STATE/{c++} c>=2{f=0}')"
if echo "$PAUSED_STEP_BLOCK" | grep -F "steps.autoreview_state.outputs.state != 'active'" > /dev/null && \
   echo "$PAUSED_STEP_BLOCK" | grep -F 'AUTOREVIEW_STATE' > /dev/null; then
  pass "paused/ignored 時（state != active）に vibehawk status を post する専用 step がある（Issue #295、merge ブロック防止）"
else
  fail "paused/ignored 時の success post step が存在しない（Issue #295）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
