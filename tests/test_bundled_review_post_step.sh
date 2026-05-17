#!/usr/bin/env bash
# Issue #152 / #164 fix の新 step「vibehawk bundled review を post」の実行検証ハーネス
#
# 目的: workflow step の本体（run: ブロック）を bash として実行し、`gh api -X POST` の
# 呼び出し回数を gh スタブで観測する。これにより以下の完了条件を実行時に検証する:
#
#   1. 正常 STRUCTURED_OUTPUT が存在 → `gh api -X POST .../pulls/N/reviews --input` が **1 回だけ** 呼ばれる
#   2. STRUCTURED_OUTPUT 破損（必須キー欠如・event 値不正 等） → `jq -e` 検証で fail → POST 0 回
#   3. 特殊文字（JSON エスケープ済 `\n` / `\"` / マルチバイト + 絵文字）を含む STRUCTURED_OUTPUT
#      → `printf '%s'` がデータを破壊せず jq 検証を通過 → POST 1 回（CISO Issue #164 必須条件）
#
# 設計:
# - workflow.yml から `vibehawk bundled review を post` step の run: ブロック本体を awk で抽出
# - 一時 PATH に gh スタブを配置（呼び出し回数を $TMPDIR/gh-call-count に追記）
# - jq は実コマンド（macOS / ubuntu-latest ともに利用可）
# - STRUCTURED_OUTPUT / RUNNER_TEMP / REPO / PR_NUMBER / GH_TOKEN を env で設定（Issue #164 fix で
#   `$GITHUB_WORKSPACE/vibehawk-review.json` 経由から `$STRUCTURED_OUTPUT` env 経由に切り替わった）

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

echo "=== Issue #152 / #164 新 step「vibehawk bundled review を post」の実行検証 ==="

# workflow.yml から該当 step の run: ブロック本体を抽出する。
# 抽出方針:
#   - "vibehawk bundled review を post（Issue ...）" の name 行から始める（Issue #152 → #164 fix で
#     name の括弧内バージョン表記が更新される可能性に追従するため、固定表記の前半のみで一致させる）
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
  # 共通環境変数: REPO / PR_NUMBER / GH_TOKEN / RUNNER_TEMP / STRUCTURED_OUTPUT / DECIDED_EVENT
  # gh スタブを PATH 先頭に追加して実 gh より優先させる
  # Issue #164 fix で `$GITHUB_WORKSPACE` 経由（ファイル事前生成）から `$STRUCTURED_OUTPUT` env
  # 経由（step 内で `${RUNNER_TEMP}` に書き出し）に切り替わった。
  # Issue #166: bundled POST step が DECIDED_EVENT 必須化（decide_event step の出力を受け取って
  # event フィールドを上書きする）。test では `DECIDED_EVENT` 環境変数を設定してから run_step を
  # 呼ぶ（未設定の場合は step が safe skip で POST 0 回となる、これも Issue #166 の正規仕様）。
  GH_CALL_LOG="${TEST_TMP}/gh-call.log" \
  GH_POST_LOG="${TEST_TMP}/gh-post.log" \
  PATH="${TEST_TMP}/bin:${PATH}" \
  REPO="hirokimry/vibehawk" \
  PR_NUMBER="153" \
  GH_TOKEN="test-token" \
  RUNNER_TEMP="${TEST_TMP}/runner-temp" \
  STRUCTURED_OUTPUT="${STRUCTURED_OUTPUT:-}" \
  DECIDED_EVENT="${DECIDED_EVENT:-}" \
  bash "${STEP_SCRIPT}"
}

reset_logs() {
  : > "${TEST_TMP}/gh-call.log"
  : > "${TEST_TMP}/gh-post.log"
  rm -rf "${TEST_TMP}/runner-temp"
  mkdir -p "${TEST_TMP}/runner-temp"
  unset STRUCTURED_OUTPUT
  unset DECIDED_EVENT
}

count_posts() {
  if [[ -f "${TEST_TMP}/gh-post.log" ]]; then
    wc -l < "${TEST_TMP}/gh-post.log" | tr -d ' '
  else
    echo "0"
  fi
}

echo ""
echo "--- ケース 1: 正常 JSON + DECIDED_EVENT=APPROVE → POST 1 回（Issue #166: bundled POST が DECIDED_EVENT 必須） ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"<!-- vibehawk:summary -->\n<!-- vibehawk:sha=deadbeef -->\nテストサマリ","commit_id":"deadbeef","comments":[]}'
DECIDED_EVENT='APPROVE'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-1.log" 2>&1; then
  pass "正常 JSON + DECIDED_EVENT で step が exit 0"
else
  fail "正常 JSON + DECIDED_EVENT で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "正常 JSON + DECIDED_EVENT で gh api -X POST が 1 回だけ呼ばれた（実測: $posts 回）"
else
  fail "正常 JSON + DECIDED_EVENT で gh api -X POST 呼び出し回数が想定外（期待: 1, 実測: $posts）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース 2: 必須キー欠如 JSON（event 不在） → POST 0 回 ---"
reset_logs
STRUCTURED_OUTPUT='{"body":"test body","commit_id":"deadbeef","comments":[]}'
export STRUCTURED_OUTPUT
if run_step > "${TEST_TMP}/step-stdout-2.log" 2>&1; then
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
unset STRUCTURED_OUTPUT

echo ""
echo "--- ケース 3: comments が配列でない JSON → POST 0 回 ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"APPROVE","body":"test body","commit_id":"deadbeef","comments":"not-an-array"}'
export STRUCTURED_OUTPUT
if run_step > "${TEST_TMP}/step-stdout-3.log" 2>&1; then
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
unset STRUCTURED_OUTPUT

echo ""
echo "--- ケース 4: COMMENT placeholder + DECIDED_EVENT=REQUEST_CHANGES → event 上書き後 POST 1 回 ---"
reset_logs
# Issue #166: Claude が placeholder として COMMENT を返しても、DECIDED_EVENT=REQUEST_CHANGES
# で event が上書きされてから POST されることを検証する。
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"<!-- vibehawk:summary -->\n<!-- vibehawk:sha=feedbeef -->\nテストサマリ","commit_id":"feedbeef","comments":[{"path":"src/foo.ts","line":42,"side":"RIGHT","body":"🟠 **Major**: test"}]}'
DECIDED_EVENT='REQUEST_CHANGES'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-4.log" 2>&1; then
  pass "COMMENT placeholder + DECIDED_EVENT=REQUEST_CHANGES で step が exit 0"
else
  fail "COMMENT placeholder + DECIDED_EVENT=REQUEST_CHANGES で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "COMMENT placeholder + DECIDED_EVENT=REQUEST_CHANGES で gh api -X POST が 1 回だけ（実測: $posts 回）"
else
  fail "COMMENT placeholder + DECIDED_EVENT=REQUEST_CHANGES で POST 回数が想定外（期待: 1, 実測: $posts）"
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

# Issue #166: POST に渡された payload の event が DECIDED_EVENT で上書きされていることを検証
# `printf '%s'` で書かれた PAYLOAD を読み取り、最終的に jq の `.event = $ev` が適用されたかを
# 検証する。step 内で PAYLOAD = ${RUNNER_TEMP}/vibehawk-review.json に書かれ、jq で上書きされる。
if [[ -f "${TEST_TMP}/runner-temp/vibehawk-review.json" ]]; then
  final_event="$(jq -r '.event' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  if [[ "$final_event" == "REQUEST_CHANGES" ]]; then
    pass "Issue #166: POST 時点の payload.event が DECIDED_EVENT (REQUEST_CHANGES) で上書きされている（Claude placeholder 'COMMENT' は捨てられた）"
  else
    fail "Issue #166: POST 時点の payload.event が上書きされていない（期待: REQUEST_CHANGES, 実測: ${final_event}）"
  fi
else
  fail "Issue #166: PAYLOAD ファイルが POST 後に残っていない（書き出し経路が壊れている）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

# PR #153 CodeRabbit Major 指摘対応で強化された JSON 検証の追加検証
# （event 値不正 / body 空文字 / commit_id 空文字 / comments[] shape 不正で POST されないこと）

echo ""
echo "--- ケース 5: event 値が不正（INVALID） → POST 0 回（JSON 検証で skip） ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"INVALID_EVENT","body":"test body","commit_id":"deadbeef","comments":[]}'
DECIDED_EVENT='APPROVE'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-5.log" 2>&1; then
  pass "event 値不正 JSON でも step が exit 0（warning + skip）"
else
  fail "event 値不正 JSON で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "0" ]]; then
  pass "event 値不正 JSON で gh api -X POST が呼ばれない（実測: $posts 回、GitHub API 契約違反の事前検知 / DECIDED_EVENT があっても JSON 検証が先に fail）"
else
  fail "event 値不正 JSON で gh api -X POST が呼ばれた（期待: 0, 実測: $posts、API 422 を招く）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース 6: body が空文字 → POST 0 回 ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"APPROVE","body":"","commit_id":"deadbeef","comments":[]}'
DECIDED_EVENT='APPROVE'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-6.log" 2>&1; then
  pass "body 空文字 JSON でも step が exit 0"
else
  fail "body 空文字 JSON で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "0" ]]; then
  pass "body 空文字 JSON で gh api -X POST が呼ばれない（実測: $posts 回）"
else
  fail "body 空文字 JSON で gh api -X POST が呼ばれた（期待: 0, 実測: $posts）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース 7: comments[].path が空文字 → POST 0 回 ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"REQUEST_CHANGES","body":"test body","commit_id":"deadbeef","comments":[{"path":"","line":1,"body":"🟠 **Major**: test"}]}'
DECIDED_EVENT='REQUEST_CHANGES'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-7.log" 2>&1; then
  pass "comments[].path 空文字 JSON でも step が exit 0"
else
  fail "comments[].path 空文字 JSON で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "0" ]]; then
  pass "comments[].path 空文字 JSON で gh api -X POST が呼ばれない（実測: $posts 回）"
else
  fail "comments[].path 空文字 JSON で gh api -X POST が呼ばれた（期待: 0, 実測: $posts）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース 8: COMMENT event の正常 JSON + DECIDED_EVENT=COMMENT → POST 1 回 ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"<!-- vibehawk:summary -->\nテストコメント","commit_id":"cafebabe","comments":[]}'
DECIDED_EVENT='COMMENT'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-8.log" 2>&1; then
  pass "COMMENT event の正常 JSON + DECIDED_EVENT=COMMENT で step が exit 0"
else
  fail "COMMENT event の正常 JSON + DECIDED_EVENT=COMMENT で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "COMMENT event の正常 JSON で gh api -X POST が 1 回だけ（実測: $posts 回、APPROVE/REQUEST_CHANGES/COMMENT 全て受理）"
else
  fail "COMMENT event の正常 JSON で POST 回数が想定外（期待: 1, 実測: $posts）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

# Issue #164 fix CISO 必須条件（追加懸念 A）: 特殊文字を含む STRUCTURED_OUTPUT で
# `printf '%s'` がデータを破壊せず jq 検証を通過することを境界テストで担保する。
# ここが壊れると不正 JSON が gh api に到達するか、bundled POST が 422 で失敗し merge gate が
# neutral に倒れる（可用性リスク、CISO「条件付き承認」必須条件）。

echo ""
echo "--- ケース 9: comments[].body に JSON エスケープ済み改行 \\n を含む → POST 1 回（CISO Issue #164 必須） ---"
reset_logs
# JSON エスケープ済み改行（\\n は JSON 文字列内では改行を表すリテラル 2 文字）。bash 変数に
# 入る時点では実際の改行ではなくバックスラッシュ + n の 2 文字を保持し、jq がそれを JSON
# string として解釈する。`printf '%s'` がこの 2 文字を破壊しないことを検証する。
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"summary","commit_id":"deadbeef","comments":[{"path":"src/foo.ts","line":1,"body":"line1\nline2\nline3"}]}'
DECIDED_EVENT='REQUEST_CHANGES'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-9.log" 2>&1; then
  pass "JSON エスケープ済み改行を含む STRUCTURED_OUTPUT で step が exit 0"
else
  fail "JSON エスケープ済み改行を含む STRUCTURED_OUTPUT で step が非ゼロ終了（printf '%s' がデータ破壊）"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "JSON エスケープ改行を含む STRUCTURED_OUTPUT で POST 1 回（実測: $posts 回、printf '%s' が改行を破壊せず）"
else
  fail "JSON エスケープ改行を含む STRUCTURED_OUTPUT で POST 回数想定外（期待: 1, 実測: $posts、CISO 必須条件 A 違反）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース 10: body に JSON エスケープ済み二重引用符 \\\" を含む → POST 1 回（CISO Issue #164 必須） ---"
reset_logs
# JSON 内で `\"` は文字列リテラル 2 文字（バックスラッシュ + ダブルクォート）。
# bash の single quote で囲んでいる限り、外側 shell の解釈は入らない。
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"quote test: \"hello world\" and \"foo\"","commit_id":"deadbeef","comments":[]}'
DECIDED_EVENT='APPROVE'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-10.log" 2>&1; then
  pass "JSON エスケープ済み二重引用符を含む STRUCTURED_OUTPUT で step が exit 0"
else
  fail "JSON エスケープ済み二重引用符を含む STRUCTURED_OUTPUT で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "JSON エスケープ二重引用符を含む STRUCTURED_OUTPUT で POST 1 回（実測: $posts 回、printf '%s' が \" を破壊せず）"
else
  fail "JSON エスケープ二重引用符を含む STRUCTURED_OUTPUT で POST 回数想定外（期待: 1, 実測: $posts、CISO 必須条件 A 違反）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース 11: body にマルチバイト文字 + 絵文字 を含む → POST 1 回（CISO Issue #164 必須） ---"
reset_logs
# 日本語 + 絵文字（severity マーカー 🟠 / 🔴 等が実運用で必ず含まれる）。UTF-8 マルチバイトが
# `printf '%s'` で破壊されないことを検証する。
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"🚨 vibehawk: 重要な指摘あり / Critical 1 件、Major 2 件","commit_id":"cafebabe","comments":[{"path":"src/日本語.ts","line":1,"body":"🟠 **Major**: 日本語による指摘内容、改行や絵文字 🎉 も含む"}]}'
DECIDED_EVENT='REQUEST_CHANGES'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-11.log" 2>&1; then
  pass "マルチバイト + 絵文字を含む STRUCTURED_OUTPUT で step が exit 0"
else
  fail "マルチバイト + 絵文字を含む STRUCTURED_OUTPUT で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "マルチバイト + 絵文字を含む STRUCTURED_OUTPUT で POST 1 回（実測: $posts 回、printf '%s' が UTF-8 を破壊せず）"
else
  fail "マルチバイト + 絵文字を含む STRUCTURED_OUTPUT で POST 回数想定外（期待: 1, 実測: $posts、CISO 必須条件 A 違反）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

# Issue #166: DECIDED_EVENT 不在時の safe skip 検証
echo ""
echo "--- ケース 12 (Issue #166): DECIDED_EVENT 未設定 → POST 0 回（decide_event step 失敗時の防御） ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"summary","commit_id":"deadbeef","comments":[]}'
export STRUCTURED_OUTPUT
# DECIDED_EVENT は意図的に export しない（unset 状態のまま run_step を呼ぶ）
if run_step > "${TEST_TMP}/step-stdout-12.log" 2>&1; then
  pass "Issue #166: DECIDED_EVENT 未設定で step が exit 0（safe skip）"
else
  fail "Issue #166: DECIDED_EVENT 未設定で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "0" ]]; then
  pass "Issue #166: DECIDED_EVENT 未設定で gh api -X POST が呼ばれない（実測: $posts 回、decide_event 失敗時の防御）"
else
  fail "Issue #166: DECIDED_EVENT 未設定で gh api -X POST が呼ばれた（期待: 0, 実測: $posts）"
fi
unset STRUCTURED_OUTPUT

# Issue #166: DECIDED_EVENT が不正値時の safe skip 検証
echo ""
echo "--- ケース 13 (Issue #166): DECIDED_EVENT='BOGUS' → POST 0 回（不正値防御） ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"summary","commit_id":"deadbeef","comments":[]}'
DECIDED_EVENT='BOGUS_VALUE'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-13.log" 2>&1; then
  pass "Issue #166: DECIDED_EVENT 不正値で step が exit 0（safe skip）"
else
  fail "Issue #166: DECIDED_EVENT 不正値で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "0" ]]; then
  pass "Issue #166: DECIDED_EVENT 不正値で gh api -X POST が呼ばれない（実測: $posts 回、不正値防御）"
else
  fail "Issue #166: DECIDED_EVENT 不正値で gh api -X POST が呼ばれた（期待: 0, 実測: $posts、API 422 を招く）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

# Issue #166: Claude が APPROVE を返しても DECIDED_EVENT=REQUEST_CHANGES で上書きされる
echo ""
echo "--- ケース 14 (Issue #166): Claude event=APPROVE 但し DECIDED_EVENT=REQUEST_CHANGES → POST 後 payload.event=REQUEST_CHANGES ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"APPROVE","body":"summary","commit_id":"deadbeef","comments":[]}'
DECIDED_EVENT='REQUEST_CHANGES'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-14.log" 2>&1; then
  pass "Issue #166: Claude APPROVE + DECIDED_EVENT REQUEST_CHANGES で step が exit 0"
else
  fail "Issue #166: Claude APPROVE + DECIDED_EVENT REQUEST_CHANGES で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "Issue #166: Claude APPROVE + DECIDED_EVENT REQUEST_CHANGES で POST 1 回（実測: $posts 回）"
else
  fail "Issue #166: Claude APPROVE + DECIDED_EVENT REQUEST_CHANGES で POST 回数想定外（期待: 1, 実測: $posts）"
fi
if [[ -f "${TEST_TMP}/runner-temp/vibehawk-review.json" ]]; then
  final_event="$(jq -r '.event' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  if [[ "$final_event" == "REQUEST_CHANGES" ]]; then
    pass "Issue #166: Claude が APPROVE を返しても DECIDED_EVENT=REQUEST_CHANGES で上書きされる（最終 payload.event=${final_event}）"
  else
    fail "Issue #166: event 上書きが効いていない（期待: REQUEST_CHANGES, 実測: ${final_event}、Claude の確率的応答に依存している）"
  fi
else
  fail "Issue #166: PAYLOAD ファイルが POST 後に残っていない"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
