#!/usr/bin/env bash
# tests/test_prepare_release.sh
#
# scripts/ci/release/prepare-release.sh の単体テスト（Issue #307）。
#
# 検証内容:
#   1. ファイル存在 / shebang / set -euo pipefail
#   2. docs のみ → 変更なし（package.json 据え置き・stdout 空）
#   3. feat 混在 → minor bump（package.json 更新・stdout は新バージョンのみ）
#   4. CHANGELOG.md に新バージョンセクションが既存履歴の上に挿入される

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/release/prepare-release.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/release/prepare-release.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "prepare-release.sh が存在する"
else
  fail "prepare-release.sh が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

if [[ "$(head -n 1 "$SCRIPT")" == "#!/usr/bin/env bash" ]]; then
  pass "shebang が #!/usr/bin/env bash"
else
  fail "shebang が想定外"
fi

if grep -qE "^set -euo pipefail$" "$SCRIPT"; then
  pass "set -euo pipefail を備える"
else
  fail "set -euo pipefail がない"
fi

if ! command -v node > /dev/null 2>&1 || ! command -v npm > /dev/null 2>&1 || ! command -v git > /dev/null 2>&1; then
  fail "node / npm / git のいずれかが PATH にない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$TMP_ROOT" || true; }
trap cleanup EXIT

setup_repo() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name tester
  printf '{\n  "name": "fixture",\n  "version": "0.1.0"\n}\n' > "${dir}/package.json"
  printf '# CHANGELOG\n\n## Unreleased\n\n## v0.1.0 - 2026-05-10\n\n- init\n' > "${dir}/CHANGELOG.md"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "init"
  git -C "$dir" tag v0.1.0
}

# --- case: docs のみ → 変更なし ---
R1="${TMP_ROOT}/r1"
mkdir -p "$R1"
setup_repo "$R1"
git -C "$R1" commit -q --allow-empty -m "📖 docs: 説明追記"
out1="$(cd "$R1" && bash "$SCRIPT" 2> /dev/null)"
ver1="$(node -p "require('${R1}/package.json').version")"
if [[ -z "$out1" && "$ver1" == "0.1.0" ]]; then
  pass "docs のみ → bump せず stdout 空・version 据え置き"
else
  fail "docs のみで変更が発生した（stdout='$out1' version='$ver1'）"
fi

# --- case: feat+fix → minor bump 0.2.0 ---
R2="${TMP_ROOT}/r2"
mkdir -p "$R2"
setup_repo "$R2"
git -C "$R2" commit -q --allow-empty -m "✨ feat: 新機能"
git -C "$R2" commit -q --allow-empty -m "🐛 fix: 不具合修正"
out2="$(cd "$R2" && bash "$SCRIPT" 2> /dev/null)"
ver2="$(node -p "require('${R2}/package.json').version")"
if [[ "$out2" == "0.2.0" ]]; then
  pass "feat 混在 → stdout が新バージョン 0.2.0 のみ"
else
  fail "stdout が想定外（'$out2'）"
fi
if [[ "$ver2" == "0.2.0" ]]; then
  pass "package.json version が 0.2.0 に bump される"
else
  fail "package.json version が想定外（'$ver2'）"
fi

# --- CHANGELOG 検証 ---
changelog2="${R2}/CHANGELOG.md"
if grep -qE "^## v0\.2\.0 - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$changelog2"; then
  pass "CHANGELOG に新バージョン見出し（## v0.2.0 - 日付）が追記される"
else
  fail "CHANGELOG の新バージョン見出しが想定と異なる"
fi
if grep -qF -- "- 新機能 (" "$changelog2" && grep -qF -- "- 不具合修正 (" "$changelog2"; then
  pass "CHANGELOG に各変更の説明が載る"
else
  fail "CHANGELOG の変更説明が想定と異なる"
fi
# 既存履歴（v0.1.0）が残り、新セクションがその上にある
line_new="$(grep -nE '^## v0\.2\.0' "$changelog2" | head -n1 | cut -d: -f1)"
line_old="$(grep -nE '^## v0\.1\.0' "$changelog2" | head -n1 | cut -d: -f1)"
if [[ -n "$line_new" && -n "$line_old" && "$line_new" -lt "$line_old" ]]; then
  pass "新セクションが既存 v0.1.0 の上に挿入される（履歴を壊さない）"
else
  fail "セクション順序が想定外（new=$line_new old=$line_old）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
