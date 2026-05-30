#!/usr/bin/env bash
# scripts/ci/vibehawk-review/assemble-inline-bodies.sh の単体テスト（Issue #263）。
#
# 構造化フィールド（category / severity / effort / title / description / suggestion? / ai_prompt）
# から CodeRabbit 互換の body を決定論的に組み立て、GitHub Reviews API 有効フィールドのみへ
# 絞り込むことを検証する。decide-event.sh の件数主軸を壊さないため .comments 件数不変も確認する。

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

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/assemble-inline-bodies.sh"

echo "=== scripts/ci/vibehawk-review/assemble-inline-bodies.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "assemble-inline-bodies.sh が存在する"
else
  fail "assemble-inline-bodies.sh が存在しない"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR" || true' EXIT

FIX="${TMP_DIR}/payload.json"

# comment0: suggestion あり + line/side あり / comment1: suggestion なし + line/side なし
cat > "$FIX" <<'JSON'
{
  "event": "COMMENT",
  "body": "サマリ本文",
  "commit_id": "deadbeef",
  "comments": [
    {
      "path": "src/a.ts",
      "line": 42,
      "side": "RIGHT",
      "category": "⚠️ Potential issue",
      "severity": "🟠 Major",
      "effort": "⚡ Quick win",
      "title": "タイトルA",
      "description": "説明Aの段落",
      "suggestion": "const userCount = users.length;",
      "ai_prompt": "src/a.ts の 42 行目付近で users.length を userCount に束ねる"
    },
    {
      "path": "src/b.ts",
      "category": "🛠️ Refactor suggestion",
      "severity": "🟡 Minor",
      "effort": "🏗️ Heavy lift",
      "title": "タイトルB",
      "description": "説明Bの段落",
      "ai_prompt": "src/b.ts の責務を分割する"
    }
  ]
}
JSON

bash "$SCRIPT" "$FIX" > /dev/null

# --- Case: 件数不変（decide-event 件数主軸の非破壊担保） ---
if [[ "$(jq '.comments | length' "$FIX")" == "2" ]]; then
  pass "comments 件数が入出力で不変（2 件）"
else
  fail "comments 件数が変化した"
fi

# --- Case: トップレベルフィールドが保持される ---
if [[ "$(jq -r '.event' "$FIX")" == "COMMENT" && "$(jq -r '.commit_id' "$FIX")" == "deadbeef" ]]; then
  pass "トップレベル event / commit_id が保持される"
else
  fail "トップレベルフィールドが壊れた"
fi

body0="$(jq -r '.comments[0].body' "$FIX")"
body1="$(jq -r '.comments[1].body' "$FIX")"

# --- Case: comment0 の 3 軸ラベル / 太字タイトル / 説明 ---
if printf '%s' "$body0" | grep -qF '_⚠️ Potential issue_ | _🟠 Major_ | _⚡ Quick win_' \
  && printf '%s' "$body0" | grep -qF '**タイトルA**' \
  && printf '%s' "$body0" | grep -qF '説明Aの段落'; then
  pass "comment0: 3 軸ラベル + 太字タイトル + 説明段落が出る"
else
  fail "comment0: 3 軸ラベル/タイトル/説明の組み立てが欠けている"
fi

# --- Case: comment0 の Committable suggestion 折り畳み ---
if printf '%s' "$body0" | grep -qF '<!-- suggestion_start -->' \
  && printf '%s' "$body0" | grep -qF '📝 Committable suggestion' \
  && printf '%s' "$body0" | grep -qF '```suggestion' \
  && printf '%s' "$body0" | grep -qF 'const userCount = users.length;' \
  && printf '%s' "$body0" | grep -qF '<!-- suggestion_end -->'; then
  pass "comment0: Committable suggestion 折り畳みでラップされる"
else
  fail "comment0: Committable suggestion 折り畳みが欠けている"
fi

# --- Case: comment0 の 🤖 AI 向け修正指示 + vibehawk:inline フッタ ---
if printf '%s' "$body0" | grep -qF '🤖 AI 向け修正指示' \
  && printf '%s' "$body0" | grep -qF 'src/a.ts の 42 行目付近で' \
  && [[ "$(printf '%s' "$body0" | tail -n 1)" == '<!-- vibehawk:inline -->' ]]; then
  pass "comment0: 🤖 折り畳み + 最終行 vibehawk:inline フッタ"
else
  fail "comment0: 🤖 折り畳み or vibehawk:inline フッタが欠けている"
fi

# --- Case: comment1（suggestion なし）は折り畳みが出ない ---
if ! printf '%s' "$body1" | grep -qF '<!-- suggestion_start -->' \
  && ! printf '%s' "$body1" | grep -qF '📝 Committable suggestion'; then
  pass "comment1: suggestion が無いと Committable suggestion 折り畳みが出ない"
else
  fail "comment1: suggestion 無しなのに折り畳みが出た"
fi

# --- Case: comment1 でも 3 軸ラベル / 🤖 / フッタは出る ---
if printf '%s' "$body1" | grep -qF '_🛠️ Refactor suggestion_ | _🟡 Minor_ | _🏗️ Heavy lift_' \
  && printf '%s' "$body1" | grep -qF '🤖 AI 向け修正指示' \
  && [[ "$(printf '%s' "$body1" | tail -n 1)" == '<!-- vibehawk:inline -->' ]]; then
  pass "comment1: 3 軸ラベル + 🤖 折り畳み + vibehawk:inline フッタが出る"
else
  fail "comment1: 3 軸ラベル/🤖/フッタが欠けている"
fi

# --- Case: 構造化フィールドが除去され GitHub API 有効フィールドのみ残る ---
keys0="$(jq -c '.comments[0] | keys' "$FIX")"
if [[ "$keys0" == '["body","line","path","side"]' ]]; then
  pass "comment0: 出力キーが path/line/side/body のみ（構造化フィールド除去）"
else
  fail "comment0: 出力キーが想定外（${keys0}）"
fi

# --- Case: line/side 欠落 comment でキーを捏造しない ---
keys1="$(jq -c '.comments[1] | keys' "$FIX")"
if [[ "$keys1" == '["body","path"]' ]]; then
  pass "comment1: line/side 欠落時にキーを捏造しない（path/body のみ）"
else
  fail "comment1: 欠落キーを捏造した（${keys1}）"
fi

# --- Case: comments が配列でない不正入力は素通し（検証 skip 経路を奪わない） ---
NONARR="${TMP_DIR}/nonarray.json"
printf '%s' '{"event":"APPROVE","body":"s","commit_id":"c","comments":"not-an-array"}' > "$NONARR"
set +e
bash "$SCRIPT" "$NONARR" > /dev/null 2>&1
rc_na=$?
set -e
if [[ "$rc_na" -eq 0 ]] && [[ "$(jq -r '.comments' "$NONARR")" == "not-an-array" ]]; then
  pass "comments が配列でない入力は変換せず素通し（exit 0）"
else
  fail "非配列 comments の素通しが機能しない（rc=${rc_na}）"
fi

# --- Case: payload ファイル不在で exit 1 ---
set +e
bash "$SCRIPT" "${TMP_DIR}/notexist.json" > /dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 1 ]]; then
  pass "payload 不在で exit 1"
else
  fail "payload 不在で exit 1 にならない（rc=${rc}）"
fi

echo "==="
echo "passed: ${PASSED}, failed: ${FAILED}"
exit "$FAILED"
