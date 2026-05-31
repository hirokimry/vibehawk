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

WORKFLOW_RAW="${REPO_ROOT}/templates/.github/workflows/vibehawk-review.yml"

if [[ ! -f "$WORKFLOW_RAW" ]]; then
  fail "${WORKFLOW_RAW} が存在しない"
  exit 1
fi
pass "${WORKFLOW_RAW} が存在する"

# Issue #176: ラッパー展開
# `run: bash scripts/ci/vibehawk-review/<name>.sh` を当該 .sh の中身に inline 展開した
# 「擬似 yaml」を作成する。本テストは awk で run ブロック本体を抽出して bash 実行するため、
# wrapper-call 形式（1 行）のままでは run ブロックを抽出できない（line 1 のラッパー呼び出ししか
# 取れない）。展開後の yaml に対して既存の awk 抽出ロジックを適用することで、Issue #176 の
# 挙動不変リファクタを越えて本ステップ実行検証が維持される。
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

pattern = re.compile(r'^(\s+)run:\s+bash\s+(scripts/ci/\S+\.sh)\s*$', re.MULTILINE)

def replace(match):
    indent = match.group(1)
    rel = match.group(2).strip()
    abs_path = os.path.join(repo_root, rel)
    # 参照先 .sh が無いケースは「壊れた参照」として即エラー終了する
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

# Issue #263: post-bundled-review.sh は同階層の assemble-inline-bodies.sh を
# `$(dirname "$0")` で呼ぶ。inline 展開した step-body.sh は TEST_TMP に置かれるため、
# 同階層に assemble スクリプトを配置して実 workflow と同じ相対解決が成立するようにする。
cp "${REPO_ROOT}/scripts/ci/vibehawk-review/assemble-inline-bodies.sh" "${TEST_TMP}/assemble-inline-bodies.sh"
chmod +x "${TEST_TMP}/assemble-inline-bodies.sh"

# Issue #271: post-bundled-review.sh は同階層の build-bundled-body.sh も `$(dirname "$0")` で呼ぶ
# （レビュー本文を構造化フィールドから組み立てる）。同様に TEST_TMP へ配置して相対解決を成立させる。
cp "${REPO_ROOT}/scripts/ci/vibehawk-review/build-bundled-body.sh" "${TEST_TMP}/build-bundled-body.sh"
chmod +x "${TEST_TMP}/build-bundled-body.sh"

# Issue #281: post-bundled-review.sh は同階層の mark-outside-diff.sh も `$(dirname "$0")` で呼ぶ
# （diff 範囲外 inline を本文集約）。同様に TEST_TMP へ配置して相対解決を成立させる。
cp "${REPO_ROOT}/scripts/ci/vibehawk-review/mark-outside-diff.sh" "${TEST_TMP}/mark-outside-diff.sh"
chmod +x "${TEST_TMP}/mark-outside-diff.sh"

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
  fail "正常 JSON + DECIDED_EVENT で gh api -X POST 呼び出し回数が想定外（期待: 1, 実測: ${posts}）"
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
  fail "comments 型不正 JSON で gh api -X POST が呼ばれた（期待: 0, 実測: ${posts}）"
fi
unset STRUCTURED_OUTPUT

echo ""
echo "--- ケース 4: COMMENT placeholder + DECIDED_EVENT=REQUEST_CHANGES → event 上書き後 POST 1 回 ---"
reset_logs
# Issue #166: Claude が placeholder として COMMENT を返しても、DECIDED_EVENT=REQUEST_CHANGES
# で event が上書きされてから POST されることを検証する。
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"<!-- vibehawk:summary -->\n<!-- vibehawk:sha=feedbeef -->\nテストサマリ","commit_id":"feedbeef","comments":[{"path":"src/foo.ts","line":42,"side":"RIGHT","category":"⚠️ Potential issue","severity":"🟠 Major","effort":"⚡ Quick win","title":"テスト指摘","description":"テスト説明","ai_prompt":"src/foo.ts の 42 行目付近を直す"}]}'
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
  fail "COMMENT placeholder + DECIDED_EVENT=REQUEST_CHANGES で POST 回数が想定外（期待: 1, 実測: ${posts}）"
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
echo "--- ケース 6: Claude の body が空でも build-bundled-body が本文を組み立てて POST する（Issue #271/#274: body は Claude 依存ではなくなった） ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"","commit_id":"deadbeef","comments":[]}'
DECIDED_EVENT='COMMENT'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-6.log" 2>&1; then
  pass "Claude body 空 JSON でも step が exit 0"
else
  fail "Claude body 空 JSON で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "Claude body 空でも build-bundled-body が本文を組み立てて POST 1 回（Issue #271、body は組み立て側が必ず生成）"
else
  fail "Claude body 空時の POST 回数が想定外（期待: 1, 実測: ${posts}）"
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
  fail "comments[].path 空文字 JSON で gh api -X POST が呼ばれた（期待: 0, 実測: ${posts}）"
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
  fail "COMMENT event の正常 JSON で POST 回数が想定外（期待: 1, 実測: ${posts}）"
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
  fail "Issue #166: DECIDED_EVENT 未設定で gh api -X POST が呼ばれた（期待: 0, 実測: ${posts}）"
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
  fail "Issue #166: Claude APPROVE + DECIDED_EVENT REQUEST_CHANGES で POST 回数想定外（期待: 1, 実測: ${posts}）"
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

# ===== Issue #222: APPROVE 時の body / comments 抑制ロジック =====
# vibehawk-for-<owner>[bot] が APPROVE する PR レビューの body と inline comments を空に
# 上書きしてから POST する（CodeRabbit 模倣）。サマリは Issue #219 の sticky walkthrough
# コメント経路で別途残るため、レビュー本文を消しても CEO は引き続きサマリを参照できる。
# REQUEST_CHANGES / COMMENT 時は従来通り body と comments を維持する（指摘内容の伝達が必須）。

echo ""
echo "===== Issue #222: APPROVE 時の body / comments 抑制 ====="

echo ""
echo "--- ケース 15 (Issue #222): DECIDED_EVENT=APPROVE + 非空 body + comments 含む → POST 後 payload.body=\"\" / comments=[] ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"<!-- vibehawk:summary -->\n<!-- vibehawk:sha=abc123 -->\n✅ vibehawk: 未解決指摘なし\n\n## 変更サマリ\n長文サマリが続く...","commit_id":"abc123","comments":[{"path":"src/foo.ts","line":10,"side":"RIGHT","body":"⚪ **Info**: 助言コメント"}]}'
DECIDED_EVENT='APPROVE'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-15.log" 2>&1; then
  pass "Issue #222: APPROVE + 非空 body + comments で step が exit 0"
else
  fail "Issue #222: APPROVE + 非空 body + comments で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "Issue #222: APPROVE で gh api -X POST が 1 回（実測: $posts 回、抑制後でも POST は維持）"
else
  fail "Issue #222: APPROVE で POST 回数が想定外（期待: 1, 実測: ${posts}）"
fi
if [[ -f "${TEST_TMP}/runner-temp/vibehawk-review.json" ]]; then
  final_body="$(jq -r '.body' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  final_comments_count="$(jq -r '.comments | length' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  final_event="$(jq -r '.event' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  if [[ "$final_body" == "" ]]; then
    pass "Issue #222: APPROVE で payload.body が空文字に上書きされる（CodeRabbit 模倣）"
  else
    fail "Issue #222: APPROVE で payload.body が空文字に上書きされていない（実測: '${final_body}'）"
  fi
  if [[ "$final_comments_count" == "0" ]]; then
    pass "Issue #222: APPROVE で payload.comments が空配列に上書きされる（実測 length=${final_comments_count}）"
  else
    fail "Issue #222: APPROVE で payload.comments が空配列に上書きされていない（実測 length=${final_comments_count}）"
  fi
  if [[ "$final_event" == "APPROVE" ]]; then
    pass "Issue #222: APPROVE で payload.event=APPROVE が維持される（抑制と event 上書きが干渉しない）"
  else
    fail "Issue #222: APPROVE で payload.event が想定外（期待: APPROVE, 実測: ${final_event}）"
  fi
else
  fail "Issue #222: PAYLOAD ファイルが POST 後に残っていない"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース 16 (Issue #222): DECIDED_EVENT=APPROVE + 既に空 body + 空 comments → 冪等性（POST 後も空のまま） ---"
reset_logs
# 既に空 body / 空 comments を入力 → validation で body length=0 が弾かれる挙動を確認しつつ、
# 入力 body が短い場合の境界（length>0 だが極小）を「✅」1 文字でテストする。
# 抑制発動後の body は同じく空、event=APPROVE が維持される。
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"✅","commit_id":"deadbeef","comments":[]}'
DECIDED_EVENT='APPROVE'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-16.log" 2>&1; then
  pass "Issue #222: APPROVE + 極小 body + 空 comments で step が exit 0"
else
  fail "Issue #222: APPROVE + 極小 body + 空 comments で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "Issue #222: APPROVE 冪等性で gh api -X POST が 1 回（実測: $posts 回）"
else
  fail "Issue #222: APPROVE 冪等性で POST 回数が想定外（期待: 1, 実測: ${posts}）"
fi
if [[ -f "${TEST_TMP}/runner-temp/vibehawk-review.json" ]]; then
  final_body="$(jq -r '.body' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  final_comments_count="$(jq -r '.comments | length' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  if [[ "$final_body" == "" && "$final_comments_count" == "0" ]]; then
    pass "Issue #222: APPROVE 冪等性 → body=\"\" / comments=[] が維持される"
  else
    fail "Issue #222: APPROVE 冪等性が壊れている（body='${final_body}', comments length=${final_comments_count}）"
  fi
else
  fail "Issue #222: PAYLOAD ファイルが POST 後に残っていない"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース 17 (Issue #222): DECIDED_EVENT=REQUEST_CHANGES + 非空 body + comments → body / comments が維持される（regression 防止） ---"
reset_logs
# REQUEST_CHANGES では body と inline 指摘を絶対に消してはならない（指摘内容の伝達が必須）。
# 抑制ロジックが APPROVE に限定されていることを境界で検証する。
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"⚠️ vibehawk: Critical 1 件 / Major 2 件","commit_id":"feedbeef","comments":[{"path":"src/bar.ts","line":42,"side":"RIGHT","body":"🔴 **Critical**: SQL injection の余地"},{"path":"src/baz.ts","line":99,"side":"RIGHT","body":"🟠 **Major**: 認証バイパスの懸念"}]}'
DECIDED_EVENT='REQUEST_CHANGES'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-17.log" 2>&1; then
  pass "Issue #222: REQUEST_CHANGES + 非空 body + comments で step が exit 0"
else
  fail "Issue #222: REQUEST_CHANGES + 非空 body + comments で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "Issue #222: REQUEST_CHANGES で gh api -X POST が 1 回（実測: $posts 回）"
else
  fail "Issue #222: REQUEST_CHANGES で POST 回数が想定外（期待: 1, 実測: ${posts}）"
fi
if [[ -f "${TEST_TMP}/runner-temp/vibehawk-review.json" ]]; then
  final_body="$(jq -r '.body' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  final_comments_count="$(jq -r '.comments | length' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  final_event="$(jq -r '.event' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  if [[ "$final_body" != "" ]]; then
    pass "Issue #222: REQUEST_CHANGES で payload.body が維持される（regression なし、抑制は APPROVE 限定）"
  else
    fail "Issue #222: REQUEST_CHANGES で payload.body が空になっている（regression、抑制が APPROVE 以外にも発動）"
  fi
  if [[ "$final_comments_count" == "2" ]]; then
    pass "Issue #222: REQUEST_CHANGES で payload.comments が 2 件維持される（regression なし）"
  else
    fail "Issue #222: REQUEST_CHANGES で payload.comments 件数が想定外（期待: 2, 実測: ${final_comments_count}）"
  fi
  if [[ "$final_event" == "REQUEST_CHANGES" ]]; then
    pass "Issue #222: REQUEST_CHANGES で payload.event=REQUEST_CHANGES が維持される"
  else
    fail "Issue #222: REQUEST_CHANGES で payload.event が想定外（期待: REQUEST_CHANGES, 実測: ${final_event}）"
  fi
else
  fail "Issue #222: PAYLOAD ファイルが POST 後に残っていない"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース 18 (Issue #222): DECIDED_EVENT=COMMENT + 非空 body + comments → body / comments が維持される（COMMENT も抑制対象外） ---"
reset_logs
# 抑制は APPROVE に限定する。COMMENT event は GitHub UI 上 muted badge となるが、
# decide-event.sh が APPROVE / REQUEST_CHANGES を選ぶ通常運用では到達しない経路。
# それでも仕様として COMMENT で body / comments が維持されることを境界で検証する。
STRUCTURED_OUTPUT='{"event":"COMMENT","body":"ℹ️ vibehawk: 情報提供のみ","commit_id":"cafe1234","comments":[{"path":"src/qux.ts","line":1,"side":"RIGHT","body":"⚪ **Info**: 補足説明"}]}'
DECIDED_EVENT='COMMENT'
export STRUCTURED_OUTPUT DECIDED_EVENT
if run_step > "${TEST_TMP}/step-stdout-18.log" 2>&1; then
  pass "Issue #222: COMMENT + 非空 body + comments で step が exit 0"
else
  fail "Issue #222: COMMENT + 非空 body + comments で step が非ゼロ終了"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "Issue #222: COMMENT で gh api -X POST が 1 回（実測: $posts 回）"
else
  fail "Issue #222: COMMENT で POST 回数が想定外（期待: 1, 実測: ${posts}）"
fi
if [[ -f "${TEST_TMP}/runner-temp/vibehawk-review.json" ]]; then
  final_body="$(jq -r '.body' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  final_comments_count="$(jq -r '.comments | length' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  if [[ "$final_body" != "" && "$final_comments_count" == "1" ]]; then
    pass "Issue #222: COMMENT で payload.body と payload.comments が維持される（抑制は APPROVE 限定の境界確認）"
  else
    fail "Issue #222: COMMENT で抑制が誤発動した（body='${final_body}', comments length=${final_comments_count}）"
  fi
else
  fail "Issue #222: PAYLOAD ファイルが POST 後に残っていない"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

# ===== Issue #171: severity 不問・件数主軸ルールの統合実証 =====
# decide-event.sh と bundled POST step を chain 実行し、新ルール（Minor/Info 1 件 → REQUEST_CHANGES、
# 0 件 → APPROVE）が最終 payload.event に反映されることを実証する。
#
# 単純な severity 内訳判定（decide-event.sh の単体テストは tests/test_vibehawk_review_decide_event.sh
# で網羅済み）ではなく、bundled POST step との chain で「decide-event.sh が算出した DECIDED_EVENT が
# 実際に POST payload に書き込まれる」末端動作を検証する。
echo ""
echo "===== Issue #171 統合実証: decide-event.sh → bundled POST chain ====="

DECIDE_SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/decide-event.sh"
if [[ ! -f "$DECIDE_SCRIPT" ]]; then
  fail "Issue #171: decide-event.sh が見つからない（${DECIDE_SCRIPT}）"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# Issue #171 統合実証用の gh スタブ（unresolved_count=0 を返す graphql + POST カウントを継承）
ISSUE171_STUB_DIR="${TEST_TMP}/issue171-bin"
mkdir -p "$ISSUE171_STUB_DIR"
cat > "${ISSUE171_STUB_DIR}/gh" <<'GH_STUB_171_EOF'
#!/usr/bin/env bash
# Issue #171 gh スタブ:
#   - gh api graphql 呼び出しは unresolved=0 を返す（decide-event.sh が読む）
#   - gh api -X POST .../reviews 呼び出しは POST_LOG にカウントを追記する（bundled POST step が読む）
echo "$@" >> "${GH_CALL_LOG}"
if [[ "${1:-}" == "api" && "${2:-}" == "graphql" ]]; then
  printf '0\n'
  exit 0
fi
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
GH_STUB_171_EOF
chmod +x "${ISSUE171_STUB_DIR}/gh"

# decide-event.sh + bundled POST step を chain 実行するヘルパー
# 入力: $1 = STRUCTURED_OUTPUT JSON
# 出力: $TEST_TMP/decide-output に decide-event.sh の GITHUB_OUTPUT 内容、
#       $TEST_TMP/runner-temp/vibehawk-review.json に bundled POST 後の payload
run_chain() {
  local structured_output="$1"

  : > "${TEST_TMP}/gh-call.log"
  : > "${TEST_TMP}/gh-post.log"
  rm -rf "${TEST_TMP}/runner-temp"
  mkdir -p "${TEST_TMP}/runner-temp"

  # Step 1: decide-event.sh を実行して DECIDED_EVENT を算出
  local decide_output="${TEST_TMP}/decide-output"
  : > "$decide_output"
  GH_CALL_LOG="${TEST_TMP}/gh-call.log" \
  GH_POST_LOG="${TEST_TMP}/gh-post.log" \
  PATH="${ISSUE171_STUB_DIR}:${PATH}" \
  GITHUB_OUTPUT="$decide_output" \
  REPO="hirokimry/vibehawk" \
  PR_NUMBER="171" \
  STRUCTURED_OUTPUT="$structured_output" \
  RUNNER_TEMP="${TEST_TMP}/runner-temp" \
  bash "$DECIDE_SCRIPT" > "${TEST_TMP}/decide-stdout.log" 2>&1

  # 算出された DECIDED_EVENT を抽出
  local decided_event=""
  if grep -q '^decided_event=' "$decide_output"; then
    decided_event="$(grep '^decided_event=' "$decide_output" | head -1 | cut -d= -f2-)"
  fi

  # Step 2: bundled POST step を decide-event.sh が算出した DECIDED_EVENT で実行
  GH_CALL_LOG="${TEST_TMP}/gh-call.log" \
  GH_POST_LOG="${TEST_TMP}/gh-post.log" \
  PATH="${ISSUE171_STUB_DIR}:${PATH}" \
  REPO="hirokimry/vibehawk" \
  PR_NUMBER="171" \
  GH_TOKEN="test-token" \
  RUNNER_TEMP="${TEST_TMP}/runner-temp" \
  STRUCTURED_OUTPUT="$structured_output" \
  DECIDED_EVENT="$decided_event" \
  bash "${STEP_SCRIPT}" > "${TEST_TMP}/bundled-stdout.log" 2>&1

  # 算出された DECIDED_EVENT を stdout 経由で呼出側に返す
  printf '%s' "$decided_event"
}

# シナリオ A: Minor 1 件 → DECIDED_EVENT=REQUEST_CHANGES → payload.event=REQUEST_CHANGES（severity 不問）
echo ""
echo "--- Issue #171 シナリオ A: 🟡 Minor 1 件 → REQUEST_CHANGES（severity 不問の新ルール実証） ---"
MINOR_PAYLOAD='{"event":"COMMENT","body":"<!-- vibehawk:summary -->\n<!-- vibehawk:sha=deadbeef -->\nテスト","commit_id":"deadbeef","comments":[{"path":"src/foo.ts","line":42,"side":"RIGHT","body":"🟡 **Minor**: 変数名を意図がわかる名前に"}]}'
decided="$(run_chain "$MINOR_PAYLOAD")"
if [[ "$decided" == "REQUEST_CHANGES" ]]; then
  pass "Issue #171: Minor 1 件で decide-event.sh が DECIDED_EVENT=REQUEST_CHANGES を算出（severity 不問）"
else
  fail "Issue #171: Minor 1 件で DECIDED_EVENT が想定外（期待: REQUEST_CHANGES, 実測: ${decided}、旧ルール（Critical/Major のみ）に戻っている）"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "Issue #171: Minor 1 件で bundled POST が 1 回実行（実測: $posts 回）"
else
  fail "Issue #171: Minor 1 件で POST 回数が想定外（期待: 1, 実測: ${posts}）"
fi
if [[ -f "${TEST_TMP}/runner-temp/vibehawk-review.json" ]]; then
  final_event="$(jq -r '.event' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  if [[ "$final_event" == "REQUEST_CHANGES" ]]; then
    pass "Issue #171: Minor 1 件で最終 payload.event=REQUEST_CHANGES（severity 不問の chain 動作確認）"
  else
    fail "Issue #171: Minor 1 件で最終 payload.event が想定外（期待: REQUEST_CHANGES, 実測: ${final_event}）"
  fi
else
  fail "Issue #171: Minor 1 件で PAYLOAD ファイルが POST 後に残っていない"
fi

# シナリオ B: Info 1 件 → DECIDED_EVENT=REQUEST_CHANGES → payload.event=REQUEST_CHANGES
echo ""
echo "--- Issue #171 シナリオ B: ⚪ Info 1 件 → REQUEST_CHANGES（severity 不問・最弱 severity でも REQUEST_CHANGES） ---"
INFO_PAYLOAD='{"event":"COMMENT","body":"<!-- vibehawk:summary -->\n<!-- vibehawk:sha=feedbeef -->\nテスト","commit_id":"feedbeef","comments":[{"path":"src/foo.ts","line":10,"side":"RIGHT","body":"⚪ **Info**: 参考情報"}]}'
decided="$(run_chain "$INFO_PAYLOAD")"
if [[ "$decided" == "REQUEST_CHANGES" ]]; then
  pass "Issue #171: Info 1 件で decide-event.sh が DECIDED_EVENT=REQUEST_CHANGES を算出（severity 不問の核心実証）"
else
  fail "Issue #171: Info 1 件で DECIDED_EVENT が想定外（期待: REQUEST_CHANGES, 実測: ${decided}）"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "Issue #171: Info 1 件で bundled POST が 1 回実行（実測: $posts 回、chain が end-to-end で完走）"
else
  fail "Issue #171: Info 1 件で POST 回数が想定外（期待: 1, 実測: ${posts}）"
fi
if [[ -f "${TEST_TMP}/runner-temp/vibehawk-review.json" ]]; then
  final_event="$(jq -r '.event' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  if [[ "$final_event" == "REQUEST_CHANGES" ]]; then
    pass "Issue #171: Info 1 件で最終 payload.event=REQUEST_CHANGES（severity 不問の chain 動作確認）"
  else
    fail "Issue #171: Info 1 件で最終 payload.event が想定外（期待: REQUEST_CHANGES, 実測: ${final_event}）"
  fi
else
  fail "Issue #171: Info 1 件で PAYLOAD ファイルが POST 後に残っていない"
fi

# シナリオ C: 0 件 → DECIDED_EVENT=APPROVE → payload.event=APPROVE
echo ""
echo "--- Issue #171 シナリオ C: 0 件 → APPROVE（既存挙動を維持） ---"
EMPTY_PAYLOAD='{"event":"COMMENT","body":"<!-- vibehawk:summary -->\n<!-- vibehawk:sha=cafebabe -->\nテスト","commit_id":"cafebabe","comments":[]}'
decided="$(run_chain "$EMPTY_PAYLOAD")"
if [[ "$decided" == "APPROVE" ]]; then
  pass "Issue #171: 0 件で decide-event.sh が DECIDED_EVENT=APPROVE を算出（既存挙動）"
else
  fail "Issue #171: 0 件で DECIDED_EVENT が想定外（期待: APPROVE, 実測: ${decided}）"
fi
posts="$(count_posts)"
if [[ "$posts" == "1" ]]; then
  pass "Issue #171: 0 件で bundled POST が 1 回実行（実測: $posts 回、APPROVE でも 1 回 POST する）"
else
  fail "Issue #171: 0 件で POST 回数が想定外（期待: 1, 実測: ${posts}）"
fi
if [[ -f "${TEST_TMP}/runner-temp/vibehawk-review.json" ]]; then
  final_event="$(jq -r '.event' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
  if [[ "$final_event" == "APPROVE" ]]; then
    pass "Issue #171: 0 件で最終 payload.event=APPROVE（指摘 0 件で APPROVE 通過の挙動維持）"
  else
    fail "Issue #171: 0 件で最終 payload.event が想定外（期待: APPROVE, 実測: ${final_event}）"
  fi
else
  fail "Issue #171: 0 件で PAYLOAD ファイルが POST 後に残っていない"
fi

echo ""
echo "--- ケース #282-a: APPROVE + 🧹 Nitpick のみ → body を保持して POST（nitpick が消えない） ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"COMMENT","commit_id":"deadbeef","comments":[{"path":"a.sh","line":5,"category":"🧹 Nitpick","effort":"⚡ Quick win","title":"命名","description":"d","ai_prompt":"p"}]}'
DECIDED_EVENT='APPROVE'
export STRUCTURED_OUTPUT DECIDED_EVENT
run_step > "${TEST_TMP}/step-stdout-282a.log" 2>&1
posts="$(count_posts)"
final_body="$(jq -r '.body' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
final_event="$(jq -r '.event' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
if [[ "$posts" == "1" ]] && [[ "$final_event" == "APPROVE" ]] && grep -qF '🧹 Nitpick comments' <<< "$final_body"; then
  pass "Issue #282: APPROVE + nitpick で body に 🧹 Nitpick comments を保持して POST（event=APPROVE, posts=${posts}）"
else
  fail "Issue #282: APPROVE + nitpick で body が保持されていない（event=${final_event}, posts=${posts}, body長=${#final_body}）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース #282-b: APPROVE + nitpick 0（truly-clean） → body 空（従来どおり） ---"
reset_logs
STRUCTURED_OUTPUT='{"event":"COMMENT","commit_id":"deadbeef","comments":[]}'
DECIDED_EVENT='APPROVE'
export STRUCTURED_OUTPUT DECIDED_EVENT
run_step > "${TEST_TMP}/step-stdout-282b.log" 2>&1
final_body="$(jq -r '.body' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
if [[ -z "$final_body" ]]; then
  pass "Issue #222/#282: APPROVE + nitpick 0 で body を空化（truly-clean は従来どおり空）"
else
  fail "Issue #222/#282: truly-clean APPROVE で body が空でない（body長=${#final_body}）"
fi
unset STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "--- ケース #281: diff 範囲外の actionable は inline から外し本文の Outside diff range へ（422 回避） ---"
reset_logs
# a.sh の hunk 内行=9..12。line10=in-diff（inline 投稿）, line99=範囲外（本文集約）
export FILES_JSON='[{"filename":"a.sh","patch":"@@ -9,1 +9,4 @@\n ctx9\n+new10\n+new11\n+new12"}]'
STRUCTURED_OUTPUT='{"event":"COMMENT","commit_id":"deadbeef","comments":[{"path":"a.sh","line":10,"side":"RIGHT","category":"⚠️ Potential issue","severity":"🟠 Major","effort":"⚡ Quick win","title":"in","description":"d","ai_prompt":"p"},{"path":"a.sh","line":99,"side":"RIGHT","category":"⚠️ Potential issue","severity":"🟡 Minor","effort":"⚡ Quick win","title":"out","description":"d","ai_prompt":"p"}]}'
DECIDED_EVENT='REQUEST_CHANGES'
export STRUCTURED_OUTPUT DECIDED_EVENT
run_step > "${TEST_TMP}/step-stdout-281.log" 2>&1
posts="$(count_posts)"
inline_lines="$(jq -r '[.comments[].line] | @csv' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
final_body="$(jq -r '.body' "${TEST_TMP}/runner-temp/vibehawk-review.json")"
if [[ "$posts" == "1" ]] && [[ "$inline_lines" == "10" ]] \
   && grep -qF '⚠️ Outside diff range comments (1)' <<< "$final_body"; then
  pass "Issue #281: 範囲外(99)を inline から除外し本文 Outside へ集約、inline は in-diff(10) のみ POST（422 回避）"
else
  fail "Issue #281: out-of-diff の routing が想定外（posts=${posts}, inline_lines=${inline_lines}）"
fi
unset FILES_JSON STRUCTURED_OUTPUT DECIDED_EVENT

echo ""
echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
