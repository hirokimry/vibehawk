#!/usr/bin/env bash
# Issue #152 fix の新 step「vibehawk bundled review を post」の実行検証ハーネス
#
# 目的: workflow step の本体（run: ブロック）を bash として実行し、`gh api -X POST` の
# 呼び出し回数を gh スタブで観測する。これにより以下の Issue #152 完了条件を実行時に検証する:
#
#   1. 正常 JSON が存在 → `gh api -X POST .../pulls/N/reviews --input` が **1 回だけ** 呼ばれる
#   2. JSON 不在 → step が skip（POST 0 回）。実 workflow では if: hashFiles で skip するが、
#      本ハーネスでは step 本体に到達しない条件を別途検証する
#   3. JSON 破損（必須キー欠如） → `jq -e` 検証で fail → POST 0 回
#
# 設計:
# - workflow.yml から `vibehawk bundled review を post` step の run: ブロック本体を awk で抽出
# - 一時 PATH に gh スタブを配置（呼び出し回数を $TMPDIR/gh-call-count に追記）
# - jq は実コマンド（macOS / ubuntu-latest ともに利用可）
# - GITHUB_WORKSPACE / REPO / PR_NUMBER / GH_TOKEN を env で設定

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

if [[ ! -f "$WORKFLOW" ]]; then
  fail "${WORKFLOW} が存在しない"
  exit 1
fi
pass "${WORKFLOW} が存在する"

echo "=== Issue #152 新 step「vibehawk bundled review を post」の実行検証 ==="

# workflow.yml から該当 step の run: ブロック本体を抽出する。
# 抽出方針:
#   - "vibehawk bundled review を post（Issue #152 fix）" の name 行から始める
#   - "run: |" の直後から、次の step（"      - name:" で始まる行）の直前までを取り出す
#   - 各行先頭の YAML インデント（10 個の空白）を取り除いて bash として実行できる形にする
STEP_BODY="$(awk '
  /name: vibehawk bundled review を post/ { in_step = 1; next }
  in_step && /^[[:space:]]+run:[[:space:]]*\|/ { in_run = 1; next }
  in_run && /^[[:space:]]+- name:/ { in_run = 0; in_step = 0 }
  in_run { print }
' "$WORKFLOW" | sed -E 's/^          //')"

if [[ -z "$STEP_BODY" ]]; then
  fail "新 step の run ブロック本体を抽出できなかった"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi
pass "新 step の run ブロック本体を抽出できた（$(echo "$STEP_BODY" | wc -l | tr -d ' ') 行）"

# テスト共通の一時ディレクトリと gh スタブ作成
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP}"' EXIT

# gh スタブ: 全引数をログに追記、`gh api -X POST` の場合のみカウンタをインクリメント
mkdir -p "${TEST_TMP}/bin"
cat > "${TEST_TMP}/bin/gh" <<'GH_STUB_EOF'
#!/usr/bin/env bash
# gh スタブ: テスト用に gh コマンドの呼び出しを記録する
echo "$@" >> "${GH_CALL_LOG}"
# `gh api -X POST` を検出してカウンタをインクリメント
for arg in "$@"; do
  if [[ "$arg" == "-X" ]]; then
    next_is_method=1
  elif [[ "${next_is_method:-0}" == "1" ]]; then
    if [[ "$arg" == "POST" ]]; then
      echo "POST" >> "${GH_POST_LOG}"
    fi
    next_is_method=0
  fi
done
exit 0
GH_STUB_EOF
chmod +x "${TEST_TMP}/bin/gh"

# step 本体を一時ファイルに書き出す（実行可能 bash として）
STEP_SCRIPT="${TEST_TMP}/step-body.sh"
{
  echo "#!/usr/bin/env bash"
  echo "$STEP_BODY"
} > "${STEP_SCRIPT}"
chmod +x "${STEP_SCRIPT}"

run_step() {
  # 共通環境変数: REPO / PR_NUMBER / GH_TOKEN / GITHUB_WORKSPACE
  # gh スタブを PATH 先頭に追加して実 gh より優先させる
  GH_CALL_LOG="${TEST_TMP}/gh-call.log" \
  GH_POST_LOG="${TEST_TMP}/gh-post.log" \
  PATH="${TEST_TMP}/bin:${PATH}" \
  REPO="hirokimry/vibehawk" \
  PR_NUMBER="153" \
  GH_TOKEN="test-token" \
  GITHUB_WORKSPACE="${TEST_TMP}/workspace" \
  bash "${STEP_SCRIPT}"
}

reset_logs() {
  : > "${TEST_TMP}/gh-call.log"
  : > "${TEST_TMP}/gh-post.log"
  rm -rf "${TEST_TMP}/workspace"
  mkdir -p "${TEST_TMP}/workspace"
}

count_posts() {
  if [[ -f "${TEST_TMP}/gh-post.log" ]]; then
    wc -l < "${TEST_TMP}/gh-post.log" | tr -d ' '
  else
    echo "0"
  fi
}

echo ""
echo "--- ケース 1: 正常 JSON → POST 1 回 ---"
reset_logs
cat > "${TEST_TMP}/workspace/vibehawk-review.json" <<'JSON_EOF'
{
  "event": "APPROVE",
  "body": "<!-- vibehawk:summary -->\n<!-- vibehawk:sha=deadbeef -->\nテストサマリ",
  "commit_id": "deadbeef",
  "comments": []
}
JSON_EOF
if run_step 2>&1 > "${TEST_TMP}/step-stdout-1.log"; then
  pass "正常 JSON で step が exit 0"
else
  fail "正常 JSON で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "正常 JSON で gh api -X POST が 1 回だけ呼ばれた（実測: $posts 回）"
else
  fail "正常 JSON で gh api -X POST 呼び出し回数が想定外（期待: 1, 実測: $posts）"
fi

echo ""
echo "--- ケース 2: 必須キー欠如 JSON（event 不在） → POST 0 回 ---"
reset_logs
cat > "${TEST_TMP}/workspace/vibehawk-review.json" <<'JSON_EOF'
{
  "body": "test body",
  "commit_id": "deadbeef",
  "comments": []
}
JSON_EOF
if run_step 2>&1 > "${TEST_TMP}/step-stdout-2.log"; then
  pass "必須キー欠如 JSON でも step が exit 0（warning を出して skip する設計）"
else
  fail "必須キー欠如 JSON で step が非ゼロ終了（warning + skip 経路が動作していない）"
fi
posts="$(count_posts)"
if [[ "$posts" == "0" ]]; then
  pass "必須キー欠如 JSON で gh api -X POST が呼ばれない（実測: $posts 回、破損 JSON での POST 防止が機能）"
else
  fail "必須キー欠如 JSON で gh api -X POST が呼ばれた（期待: 0, 実測: $posts、破損 JSON 検証が機能していない）"
fi

echo ""
echo "--- ケース 3: comments が配列でない JSON → POST 0 回 ---"
reset_logs
cat > "${TEST_TMP}/workspace/vibehawk-review.json" <<'JSON_EOF'
{
  "event": "APPROVE",
  "body": "test body",
  "commit_id": "deadbeef",
  "comments": "not-an-array"
}
JSON_EOF
if run_step 2>&1 > "${TEST_TMP}/step-stdout-3.log"; then
  pass "comments 型不正 JSON でも step が exit 0"
else
  fail "comments 型不正 JSON で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "0" ]]; then
  pass "comments 型不正 JSON で gh api -X POST が呼ばれない（実測: $posts 回）"
else
  fail "comments 型不正 JSON で gh api -X POST が呼ばれた（期待: 0, 実測: $posts）"
fi

echo ""
echo "--- ケース 4: REQUEST_CHANGES event の正常 JSON → POST 1 回 ---"
reset_logs
cat > "${TEST_TMP}/workspace/vibehawk-review.json" <<'JSON_EOF'
{
  "event": "REQUEST_CHANGES",
  "body": "<!-- vibehawk:summary -->\n<!-- vibehawk:sha=feedbeef -->\nテストサマリ",
  "commit_id": "feedbeef",
  "comments": [
    {"path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "🟠 **Major**: test"}
  ]
}
JSON_EOF
if run_step 2>&1 > "${TEST_TMP}/step-stdout-4.log"; then
  pass "REQUEST_CHANGES + inline 1 件で step が exit 0"
else
  fail "REQUEST_CHANGES + inline 1 件で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "REQUEST_CHANGES の正常 JSON で gh api -X POST が 1 回だけ（実測: $posts 回）"
else
  fail "REQUEST_CHANGES の正常 JSON で POST 回数が想定外（期待: 1, 実測: $posts）"
fi

# POST 引数の整合性検証（最後のケースの POST が --input でファイルを参照するか）
if grep -F -- '--input' "${TEST_TMP}/gh-call.log" > /dev/null; then
  pass "gh api 呼び出しに --input が含まれる（JSON ファイルを stdin ではなく path で渡す方式）"
else
  fail "gh api 呼び出しに --input が含まれない（決定論的 POST のために --input <path> が前提）"
fi

if grep -E "repos/[^ ]+/pulls/[0-9]+/reviews" "${TEST_TMP}/gh-call.log" > /dev/null; then
  pass "gh api 呼び出しが repos/.../pulls/N/reviews エンドポイントを叩く"
else
  fail "gh api 呼び出しが reviews エンドポイントを叩いていない"
fi

echo ""
echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
