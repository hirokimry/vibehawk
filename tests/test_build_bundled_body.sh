#!/usr/bin/env bash
# Issue #271: build-bundled-body.sh のテスト
#
# 検証対象: scripts/ci/vibehawk-review/build-bundled-body.sh
# - `**Actionable comments posted: N**` 先頭行（actionable = category が 🧹 Nitpick 以外の件数）
# - 🧹 Nitpick comments (M) 折り畳み（ファイル別ネスト + 件数）
# - nitpick の描画（行参照 + effort ラベル + 太字タイトル + 説明 + 🔧 提案差分 + 🤖 AI 向け修正指示）
# - nitpick に severity を出さない（Issue #270: severity は actionable 専用）
# - 末尾マーカー（<!-- vibehawk:summary --> / <!-- vibehawk:sha=<commit_id> -->）保持

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/build-bundled-body.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

TMPDIR_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_ROOT" || true; }
trap cleanup EXIT

if [[ -f "$SCRIPT" ]]; then
  pass "build-bundled-body.sh が存在する"
else
  fail "build-bundled-body.sh が存在しない"
  exit 1
fi

# 機能: payload JSON を作って build-bundled-body.sh の出力を返す
run_build() {
  local payload="${TMPDIR_ROOT}/payload.json"
  printf '%s' "$1" > "$payload"
  bash "$SCRIPT" "$payload"
}

echo "=== Case 1: actionable 2 + nitpick 2（1 ファイル重複） ==="
PAYLOAD='{"commit_id":"abc1234","comments":[
  {"path":"a.sh","line":10,"category":"⚠️ Potential issue","severity":"🟠 Major","effort":"⚡ Quick win","title":"バグ","description":"説明A","ai_prompt":"直してA"},
  {"path":"b.sh","line":20,"category":"🛠️ Refactor suggestion","severity":"🟡 Minor","effort":"🏗️ Heavy lift","title":"構造","description":"説明B","ai_prompt":"直してB"},
  {"path":"c.sh","line":30,"start_line":28,"category":"🧹 Nitpick","effort":"⚡ Quick win","title":"命名","description":"説明C","suggestion":"new_name","ai_prompt":"直してC"},
  {"path":"c.sh","line":40,"category":"🧹 Nitpick","effort":"⚡ Quick win","title":"体裁","description":"説明D","ai_prompt":"直してD"}
]}'
out="$(run_build "$PAYLOAD")"

if grep -qF '**Actionable comments posted: 2**' <<< "$out"; then
  pass "Actionable 件数行が actionable 件数（2）を表示する"
else
  fail "Actionable 件数行が期待通りでない"
fi

if grep -qF '<summary>🧹 Nitpick comments (2)</summary>' <<< "$out"; then
  pass "🧹 Nitpick comments (2) 折り畳みが出る"
else
  fail "🧹 Nitpick comments の件数表示が期待通りでない"
fi

if grep -qF '<summary>c.sh (2)</summary>' <<< "$out"; then
  pass "nitpick がファイル別ネスト（c.sh (2)）で集約される"
else
  fail "nitpick のファイル別ネストが期待通りでない"
fi

# shellcheck disable=SC2016  # バッククォートは検証対象の markdown リテラル。展開させない。
if grep -qF '`28-30`: _⚡ Quick win_' <<< "$out"; then
  pass "start_line ありの nitpick が行範囲（28-30）+ effort ラベルで描画される"
else
  fail "nitpick の行範囲表示が期待通りでない"
fi

# shellcheck disable=SC2016  # バッククォートは検証対象の markdown リテラル。展開させない。
if grep -qF '`40`: _⚡ Quick win_' <<< "$out"; then
  pass "start_line なしの nitpick が単一行（40）+ effort ラベルで描画される"
else
  fail "nitpick の単一行表示が期待通りでない"
fi

if grep -qF '**命名**' <<< "$out" && grep -qF '説明C' <<< "$out"; then
  pass "nitpick の太字タイトル + 説明が描画される"
else
  fail "nitpick のタイトル / 説明が期待通りでない"
fi

if grep -qF '<summary>🔧 提案差分</summary>' <<< "$out" && grep -qF '```suggestion' <<< "$out"; then
  pass "suggestion ありの nitpick に 🔧 提案差分 折り畳みが付く"
else
  fail "nitpick の提案差分折り畳みが期待通りでない"
fi

if grep -qF '<summary>🤖 AI 向け修正指示</summary>' <<< "$out"; then
  pass "nitpick に 🤖 AI 向け修正指示 折り畳みが付く"
else
  fail "nitpick の AI 向け修正指示折り畳みが出ない"
fi

# Issue #270: nitpick に severity（🔴〜⚪）を出さない
if grep -qE '🔴 Critical|🟠 Major|🟡 Minor|🔵 Trivial|⚪ Info' <<< "$out"; then
  fail "本文に severity マーカーが出ている（nitpick は severity を持たないはず、Issue #270）"
else
  pass "本文に severity マーカーが出ない（nitpick は severity を持たない、Issue #270）"
fi

echo "=== Case 1b: 統合 AI プロンプト（Issue #272） ==="
if grep -qF '<summary>🤖 全指摘の AI 向け修正指示（一括）</summary>' <<< "$out"; then
  pass "🤖 全指摘の AI 向け修正指示（一括）折り畳みが出る"
else
  fail "統合 AI プロンプトの折り畳みが出ない"
fi

if grep -qF 'actionable:' <<< "$out" && grep -qF 'nitpick:' <<< "$out" \
   && grep -qF '@a.sh:' <<< "$out" && grep -qF '@c.sh:' <<< "$out"; then
  pass "統合 AI プロンプトが actionable / nitpick をファイル別（@path）に束ねる"
else
  fail "統合 AI プロンプトのファイル別グルーピングが期待通りでない"
fi

# パターンが `-` 始まりのため -- でパターン終端を明示する（shell.md）
if grep -qF -- '- 直してA' <<< "$out" && grep -qF -- '- 直してC' <<< "$out" && grep -qF -- '- 直してD' <<< "$out"; then
  pass "統合 AI プロンプトが全指摘（actionable + nitpick）の ai_prompt を含む"
else
  fail "統合 AI プロンプトに一部 ai_prompt が欠落"
fi

echo "=== Case 2: 末尾マーカー保持 ==="
if grep -qF '<!-- vibehawk:summary -->' <<< "$out" && grep -qF '<!-- vibehawk:sha=abc1234 -->' <<< "$out"; then
  pass "末尾に vibehawk:summary / vibehawk:sha マーカーが付く（incremental 検出に必須、Issue #57）"
else
  fail "末尾マーカーが欠落（incremental レビューが破綻する）"
fi

echo "=== Case 2b: env なしで ℹ️ Review info を出さない（後方互換、Issue #273） ==="
if grep -qF 'ℹ️ Review info' <<< "$out"; then
  fail "env 未設定でも ℹ️ Review info が出ている（後方互換破壊）"
else
  pass "env 未設定では ℹ️ Review info を出さない（後方互換）"
fi

echo "=== Case 2c: env ありで ℹ️ Review info を出す（Issue #273） ==="
export RUN_ID="run-9"
export COMMITS_JSON='[{"sha":"aaaaaaa1234567"},{"sha":"bbbbbbb8901234"}]'
export FILES_SELECTED_JSON='["x.sh","y.sh"]'
out_ri="$(run_build "$PAYLOAD")"
unset RUN_ID COMMITS_JSON FILES_SELECTED_JSON

if grep -qF '<summary>ℹ️ Review info</summary>' <<< "$out_ri" \
   && grep -qF '<summary>⚙️ Run configuration</summary>' <<< "$out_ri" \
   && grep -qF '| Run ID | run-9 |' <<< "$out_ri"; then
  pass "ℹ️ Review info + ⚙️ Run configuration（Run ID）が出る"
else
  fail "ℹ️ Review info / Run configuration が期待通りでない"
fi

if grep -qF 'between aaaaaaa and bbbbbbb' <<< "$out_ri" \
   && grep -qF '<summary>📒 Files selected for processing (2)</summary>' <<< "$out_ri"; then
  pass "📥 Commits（base〜head 短縮 SHA）+ 📒 Files selected (2) が出る"
else
  fail "Commits / Files selected が期待通りでない"
fi

# Review info はマーカーより前（CodeRabbit の並び順）
ri_line=$(grep -nF 'ℹ️ Review info' <<< "$out_ri" | head -1 | cut -d: -f1)
marker_line=$(grep -nF '<!-- vibehawk:summary -->' <<< "$out_ri" | head -1 | cut -d: -f1)
if [ -n "$ri_line" ] && [ -n "$marker_line" ] && [ "$ri_line" -lt "$marker_line" ]; then
  pass "ℹ️ Review info が末尾マーカーより前に出る"
else
  fail "ℹ️ Review info とマーカーの並び順が不正（ri=${ri_line} marker=${marker_line}）"
fi

echo "=== Case 3: nitpick なし（actionable のみ） ==="
out2="$(run_build '{"commit_id":"sha1","comments":[{"path":"a.sh","line":1,"category":"⚠️ Potential issue","severity":"🔴 Critical","effort":"⚡ Quick win","title":"t","description":"d","ai_prompt":"p"}]}')"
if grep -qF '**Actionable comments posted: 1**' <<< "$out2" && ! grep -qF '🧹 Nitpick comments' <<< "$out2"; then
  pass "nitpick が無いと Nitpick セクションを出さない"
else
  fail "nitpick 無し時の出力が期待通りでない"
fi

echo "=== Case 4: 0 件（Issue #282: Actionable 0 行を出さない） ==="
out3="$(run_build '{"commit_id":"sha2","comments":[]}')"
if ! grep -qF 'Actionable comments posted' <<< "$out3" && ! grep -qF '全指摘の AI 向け修正指示' <<< "$out3"; then
  pass "0 件で Actionable comments posted 行を出さず、統合 AI プロンプトも出さない（Issue #282）"
else
  fail "0 件時の出力が期待通りでない（Actionable 0 行が出ている）"
fi

echo "=== Case 5: actionable 0 + 🧹 Nitpick のみ（Issue #282: 件数行なし + nitpick あり、CodeRabbit 互換） ==="
out4="$(run_build '{"commit_id":"sha3","comments":[{"path":"a.sh","line":5,"category":"🧹 Nitpick","effort":"⚡ Quick win","title":"命名","description":"d","ai_prompt":"p"}]}')"
if ! grep -qF 'Actionable comments posted' <<< "$out4" && grep -qF '🧹 Nitpick comments (1)' <<< "$out4"; then
  pass "actionable 0 + nitpick のとき Actionable 行を出さず 🧹 Nitpick comments を出す（CodeRabbit nitpick-only 互換、Issue #282）"
else
  fail "nitpick-only 時の出力が期待通りでない"
fi

echo "=== Case 6: _outside_diff の actionable は ⚠️ Outside diff range へ、inline 件数から除外（Issue #281） ==="
out5="$(run_build '{"commit_id":"sha4","comments":[
  {"path":"a.sh","line":10,"side":"RIGHT","category":"⚠️ Potential issue","severity":"🟠 Major","effort":"⚡ Quick win","title":"in","description":"d","ai_prompt":"p","_outside_diff":false},
  {"path":"a.sh","line":99,"side":"RIGHT","category":"⚠️ Potential issue","severity":"🟡 Minor","effort":"🏗️ Heavy lift","title":"out","description":"od","ai_prompt":"op","_outside_diff":true}
]}')"
if grep -qF '**Actionable comments posted: 1**' <<< "$out5" \
   && grep -qF '⚠️ Outside diff range comments (1)' <<< "$out5" \
   && grep -qF '**out**' <<< "$out5"; then
  pass "Actionable posted は inline のみ（1）+ ⚠️ Outside diff range comments (1) に範囲外を集約（Issue #281）"
else
  fail "Outside diff range セクションの出力が期待通りでない"
fi

# 範囲外指摘も統合 AI プロンプトに含まれる（握り潰さない）
if grep -qF -- '- op' <<< "$out5"; then
  pass "範囲外指摘の ai_prompt も統合 AI プロンプトに含まれる（Issue #281）"
else
  fail "範囲外指摘が統合 AI プロンプトに含まれない"
fi

echo ""
echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
