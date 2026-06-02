#!/usr/bin/env bash
# tests/test_release_tag_on_main.sh
#
# scripts/ci/release/release-tag-on-main.sh の単体テスト（Issue #307）。
#
# gh CLI はテスト用スタブ（呼び出しを記録し、release view は常に不在=exit 1）に差し替える。
#
# 検証内容:
#   1. ファイル存在 / shebang / set -euo pipefail
#   2. version 変化なし（before==after）→ Release を作らない
#   3. version bump（before!=after）かつ tag 不在 → gh release create を呼ぶ
#   4. 既存 tag がある → Release を作らない

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/release/release-tag-on-main.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/release/release-tag-on-main.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "release-tag-on-main.sh が存在する"
else
  fail "release-tag-on-main.sh が存在しない"
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

if ! command -v jq > /dev/null 2>&1 || ! command -v git > /dev/null 2>&1; then
  fail "jq / git のいずれかが PATH にない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
STUB_BIN="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_ROOT" || true
  rm -rf "$STUB_BIN" || true
}
trap cleanup EXIT

# gh スタブ: 呼び出しを GH_LOG に記録。release view は不在扱い（exit 1）。
GH_LOG="${TMP_ROOT}/gh.log"
cat > "${STUB_BIN}/gh" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "${GH_LOG}"
if [ "\$1" = "release" ] && [ "\$2" = "view" ]; then
  exit 1
fi
exit 0
STUB
chmod +x "${STUB_BIN}/gh"

setup_repo() {
  local dir="$1"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@example.com
  git -C "$dir" config user.name tester
  printf '{\n  "version": "0.1.0"\n}\n' > "${dir}/package.json"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "init"
}

# --- case 1: version 変化なし → Release 作成しない ---
R1="${TMP_ROOT}/r1"
mkdir -p "$R1"
setup_repo "$R1"
before1="$(git -C "$R1" rev-parse HEAD)"
git -C "$R1" commit -q --allow-empty -m "🐛 fix: 何か"
after1="$(git -C "$R1" rev-parse HEAD)"
: > "$GH_LOG"
(
  cd "$R1"
  PATH="${STUB_BIN}:$PATH" BEFORE_SHA="$before1" AFTER_SHA="$after1" bash "$SCRIPT" > /dev/null 2>&1
)
if [[ ! -s "$GH_LOG" ]] || ! grep -q "release create" "$GH_LOG"; then
  pass "version 変化なし → gh release create を呼ばない"
else
  fail "version 変化なしなのに release create が呼ばれた: $(cat "$GH_LOG")"
fi

# --- case 2: version bump かつ tag 不在 → release create を呼ぶ ---
R2="${TMP_ROOT}/r2"
mkdir -p "$R2"
setup_repo "$R2"
before2="$(git -C "$R2" rev-parse HEAD)"
printf '{\n  "version": "0.2.0"\n}\n' > "${R2}/package.json"
git -C "$R2" add -A
git -C "$R2" commit -q -m "✨ feat: 大きな機能"
after2="$(git -C "$R2" rev-parse HEAD)"
: > "$GH_LOG"
(
  cd "$R2"
  PATH="${STUB_BIN}:$PATH" BEFORE_SHA="$before2" AFTER_SHA="$after2" bash "$SCRIPT" > /dev/null 2>&1
)
if grep -qE "release create v0\.2\.0" "$GH_LOG"; then
  pass "version bump → gh release create v0.2.0 を呼ぶ"
else
  fail "version bump で release create が呼ばれない: $(cat "$GH_LOG")"
fi

# --- case 3: 既存 tag あり → Release 作成しない ---
R3="${TMP_ROOT}/r3"
mkdir -p "$R3"
setup_repo "$R3"
before3="$(git -C "$R3" rev-parse HEAD)"
printf '{\n  "version": "0.2.0"\n}\n' > "${R3}/package.json"
git -C "$R3" add -A
git -C "$R3" commit -q -m "✨ feat: 機能"
after3="$(git -C "$R3" rev-parse HEAD)"
git -C "$R3" tag v0.2.0
: > "$GH_LOG"
(
  cd "$R3"
  PATH="${STUB_BIN}:$PATH" BEFORE_SHA="$before3" AFTER_SHA="$after3" bash "$SCRIPT" > /dev/null 2>&1
)
if ! grep -q "release create" "$GH_LOG"; then
  pass "既存 tag あり → gh release create を呼ばない"
else
  fail "既存 tag があるのに release create が呼ばれた: $(cat "$GH_LOG")"
fi

# --- case 4: head の package.json から version を取得できない → Release 作成しない（graceful skip、Issue #319） ---
R4="${TMP_ROOT}/r4"
mkdir -p "$R4"
setup_repo "$R4"
before4="$(git -C "$R4" rev-parse HEAD)"
# version を持たない不正な package.json にして、jq が空を返すケースを再現する
printf 'not a json\n' > "${R4}/package.json"
git -C "$R4" add -A
git -C "$R4" commit -q -m "✨ feat: 壊れた package.json"
after4="$(git -C "$R4" rev-parse HEAD)"
: > "$GH_LOG"
script_exit=0
(
  cd "$R4"
  PATH="${STUB_BIN}:$PATH" BEFORE_SHA="$before4" AFTER_SHA="$after4" bash "$SCRIPT" > /dev/null 2>&1
) || script_exit=$?
if [[ "$script_exit" -eq 0 ]] && ! grep -q "release create" "$GH_LOG"; then
  pass "version 取得不能 → set -e で abort せず gh release create も呼ばない（graceful skip）"
else
  fail "version 取得不能時の挙動が想定外（exit=$script_exit, gh=$(cat "$GH_LOG"))"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
