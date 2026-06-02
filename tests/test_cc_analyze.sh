#!/usr/bin/env bash
# tests/test_cc_analyze.sh
#
# scripts/ci/release/cc-analyze.sh の単体テスト（Issue #307）。
#
# 検証内容:
#   1. ファイル存在 / shebang / set -euo pipefail（多重 source ガード）
#   2. bump_version の semver 計算（major/minor/patch/none）
#   3. cc_analyze の bump レベル判定（feat=minor / fix=patch / breaking=major / docs=none）
#   4. リリースノートに説明文が改行で割れずに載る（git log format の改行混入対策）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="${REPO_ROOT}/scripts/ci/release/cc-analyze.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/release/cc-analyze.sh 単体テスト ==="

if [[ -f "$LIB" ]]; then
  pass "cc-analyze.sh が存在する"
else
  fail "cc-analyze.sh が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

if [[ "$(head -n 1 "$LIB")" == "#!/usr/bin/env bash" ]]; then
  pass "shebang が #!/usr/bin/env bash"
else
  fail "shebang が想定外"
fi

if ! command -v git > /dev/null 2>&1; then
  fail "git コマンドが PATH にない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# shellcheck source=../scripts/ci/release/cc-analyze.sh
. "$LIB"

# --- bump_version ---
[[ "$(bump_version 0.1.0 2)" == "0.2.0" ]] && pass "bump_version minor: 0.1.0 → 0.2.0" || fail "bump_version minor が想定外: $(bump_version 0.1.0 2)"
[[ "$(bump_version 0.1.0 1)" == "0.1.1" ]] && pass "bump_version patch: 0.1.0 → 0.1.1" || fail "bump_version patch が想定外"
[[ "$(bump_version 1.2.3 3)" == "2.0.0" ]] && pass "bump_version major: 1.2.3 → 2.0.0" || fail "bump_version major が想定外"
[[ "$(bump_version 1.2.3 0)" == "1.2.3" ]] && pass "bump_version none: 据え置き" || fail "bump_version none が想定外"

TMP_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMP_ROOT" || true; }
trap cleanup EXIT

make_repo() {
  local dir="$1"
  shift
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name tester
  git -C "$dir" commit -q --allow-empty -m "init"
  git -C "$dir" tag base
  local msg
  for msg in "$@"; do
    git -C "$dir" commit -q --allow-empty -m "$msg"
  done
}

# --- case: docs のみ → bump なし ---
R1="${TMP_ROOT}/r1"
mkdir -p "$R1"
make_repo "$R1" "📖 docs: ドキュメント整備"
(
  cd "$R1"
  cc_analyze "base..HEAD"
  [[ "$CC_BUMP_LEVEL" -eq 0 ]] || { echo "DOCS_LEVEL=$CC_BUMP_LEVEL"; exit 1; }
) && pass "docs のみ → bump レベル 0" || fail "docs のみで bump レベルが 0 でない"

# --- case: fix → patch(1) ---
R2="${TMP_ROOT}/r2"
mkdir -p "$R2"
make_repo "$R2" "🐛 fix: バグ修正"
(
  cd "$R2"
  cc_analyze "base..HEAD"
  [[ "$CC_BUMP_LEVEL" -eq 1 ]] || exit 1
) && pass "fix → bump レベル 1（patch）" || fail "fix の bump レベルが 1 でない"

# --- case: feat → minor(2) ---
R3="${TMP_ROOT}/r3"
mkdir -p "$R3"
make_repo "$R3" "🐛 fix: バグ修正" "✨ feat: 新機能"
(
  cd "$R3"
  cc_analyze "base..HEAD"
  [[ "$CC_BUMP_LEVEL" -eq 2 ]] || exit 1
) && pass "feat 混在 → bump レベル 2（minor）" || fail "feat 混在の bump レベルが 2 でない"

# --- case: breaking(!) → major(3) ---
R4="${TMP_ROOT}/r4"
mkdir -p "$R4"
make_repo "$R4" "✨ feat!: 互換性のない変更"
(
  cd "$R4"
  cc_analyze "base..HEAD"
  [[ "$CC_BUMP_LEVEL" -eq 3 ]] || exit 1
) && pass "feat! → bump レベル 3（major）" || fail "breaking の bump レベルが 3 でない"

# --- case: BREAKING CHANGE: body → major(3) ---
R5="${TMP_ROOT}/r5"
mkdir -p "$R5"
git -C "$R5" init -q
git -C "$R5" config user.email t@example.com
git -C "$R5" config user.name tester
git -C "$R5" commit -q --allow-empty -m "init"
git -C "$R5" tag base
git -C "$R5" commit -q --allow-empty -m "🔄 refactor: 内部整理" -m "BREAKING CHANGE: 公開 API が変わった"
(
  cd "$R5"
  cc_analyze "base..HEAD"
  [[ "$CC_BUMP_LEVEL" -eq 3 ]] || exit 1
) && pass "body の BREAKING CHANGE → bump レベル 3" || fail "body BREAKING CHANGE が major にならない"

# --- case: リリースノートに説明文が改行で割れない（複数コミット） ---
R6="${TMP_ROOT}/r6"
mkdir -p "$R6"
make_repo "$R6" "✨ feat: 最初の機能" "🐛 fix: 二番目の修正"
notes_out="$(
  cd "$R6"
  cc_analyze "base..HEAD"
  printf '%s' "$CC_RELEASE_NOTES"
)"
if printf '%s' "$notes_out" | grep -qE '^- 最初の機能 \(' && printf '%s' "$notes_out" | grep -qE '^- 二番目の修正 \('; then
  pass "リリースノートの説明文が改行で割れずに 1 行で載る"
else
  fail "リリースノートの説明文が想定と異なる: $notes_out"
fi
if printf '%s' "$notes_out" | grep -qF "## ✨ 新機能" && printf '%s' "$notes_out" | grep -qF "## 🐛 バグ修正"; then
  pass "カテゴリ見出し（新機能 / バグ修正）が出力される"
else
  fail "カテゴリ見出しが想定と異なる"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
