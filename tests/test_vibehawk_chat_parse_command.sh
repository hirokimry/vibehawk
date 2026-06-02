#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/parse-command.sh の単体テスト（Issue #289、CodeRabbit 指摘対応）。
#   - 厳密行一致でコマンドを判定（prose 誤発火を排除）
#   - full review を review より優先（厳密一致なので別文字列）
#   - 会話文・引用・説明は chat 扱い
#   - 余分な行（説明）が続いてもコマンド行があれば検出

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/parse-command.sh"
echo "=== parse-command.sh 単体テスト ==="
if [[ -f "$SCRIPT" ]]; then pass "存在する"; else fail "存在しない"; exit 1; fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

run() {
  # $1 COMMENT_BODY → echo command
  : > "${TMP_DIR}/out"
  COMMENT_BODY="$1" GITHUB_OUTPUT="${TMP_DIR}/out" bash "$SCRIPT" >/dev/null 2>&1
  grep '^command=' "${TMP_DIR}/out" | sed 's/^command=//'
}

assert_cmd() {
  # $1 body  $2 expected  $3 desc
  local got; got="$(run "$1")"
  if [[ "$got" == "$2" ]]; then pass "${3}（→ ${got}）"; else fail "${3}: 期待=${2} 実際=${got}"; fi
}

echo "=== 厳密コマンド検出 ==="
assert_cmd "@vibehawk review" "review" "単独 review"
assert_cmd "@vibehawk full review" "full-review" "単独 full review（review より優先）"
assert_cmd "@vibehawk resolve" "resolve" "resolve"
assert_cmd "@vibehawk summary" "summary" "summary"
assert_cmd "@vibehawk help" "help" "help"
assert_cmd "@vibehawk configuration" "configuration" "configuration"
assert_cmd "@vibehawk pause" "pause" "pause"
assert_cmd "@vibehawk resume" "resume" "resume"
assert_cmd "@vibehawk ignore" "ignore" "ignore"

echo "=== コマンド行 + 後続説明行（コマンド行が厳密一致すれば検出） ==="
assert_cmd "$(printf '@vibehawk review\n\n（CI 修正反映後の再評価依頼）')" "review" "review + 後続説明"
assert_cmd "$(printf '  @vibehawk pause  \n本文')" "pause" "前後空白付き pause 行"

echo "=== prose 誤発火の排除（chat 扱い） ==="
assert_cmd "@vibehawk review と full review の違いは?" "chat" "質問文（review/full review 含むが行全体不一致）"
assert_cmd "@vibehawk pause の説明を書きたい" "chat" "説明文（pause を含むが行全体不一致）"
assert_cmd "今日は @vibehawk resolve について相談です" "chat" "文中の resolve 言及"
assert_cmd "@vibehawk こんにちは" "chat" "通常メンション（未知語）"
assert_cmd "@vibehawk reviewer を追加して" "chat" "reviewer（review の部分文字列誤発火しない）"

echo "=== env 欠落 ==="
set +e
COMMENT_BODY="x" bash "$SCRIPT" >/dev/null 2>&1
rc1=$?
GITHUB_OUTPUT="${TMP_DIR}/out" bash "$SCRIPT" >/dev/null 2>&1
rc2=$?
set -e
if [[ "$rc1" -ne 0 && "$rc2" -ne 0 ]]; then pass "必須 env 欠落で非 0"; else fail "env 欠落でも 0 終了"; fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
