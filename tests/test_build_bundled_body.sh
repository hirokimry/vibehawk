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

echo "=== Case 2: 末尾マーカー保持 ==="
if grep -qF '<!-- vibehawk:summary -->' <<< "$out" && grep -qF '<!-- vibehawk:sha=abc1234 -->' <<< "$out"; then
  pass "末尾に vibehawk:summary / vibehawk:sha マーカーが付く（incremental 検出に必須、Issue #57）"
else
  fail "末尾マーカーが欠落（incremental レビューが破綻する）"
fi

echo "=== Case 3: nitpick なし（actionable のみ） ==="
out2="$(run_build '{"commit_id":"sha1","comments":[{"path":"a.sh","line":1,"category":"⚠️ Potential issue","severity":"🔴 Critical","effort":"⚡ Quick win","title":"t","description":"d","ai_prompt":"p"}]}')"
if grep -qF '**Actionable comments posted: 1**' <<< "$out2" && ! grep -qF '🧹 Nitpick comments' <<< "$out2"; then
  pass "nitpick が無いと Nitpick セクションを出さない"
else
  fail "nitpick 無し時の出力が期待通りでない"
fi

echo "=== Case 4: 0 件 ==="
out3="$(run_build '{"commit_id":"sha2","comments":[]}')"
if grep -qF '**Actionable comments posted: 0**' <<< "$out3"; then
  pass "0 件で Actionable comments posted: 0 を表示する"
else
  fail "0 件時の出力が期待通りでない"
fi

echo ""
echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
