#!/usr/bin/env bash
# 外部リポジトリ相当での skip-mark 自己完結化の実行系検証（Issue #350）
#
# npx vibehawk setup で配布された外部リポジトリには scripts/ci/ 配下が存在しない。
# skip-mark workflow は #346 と同じ自己完結化（hashFiles guard + pin 付き 2nd checkout +
# ${VIBEHAWK_RUNTIME}/ prefix）により、外部リポジトリでも lockfile のみ変更の PR で
# classify-paths-ignore.sh を file not found なしで実行し is_skip=true を返す。
# 本テストはその経路を一時ディレクトリで再現し、外部リポジトリでの merge gate 通過を保証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

# skip-mark workflow の hashFiles guard 相当（GitHub 式の三項演算と同じ判定）。
# guard ファイルが存在すれば自リポジトリ（.）、不在なら外部リポジトリ（.vibehawk-runtime）。
GUARD_REL="scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh"
resolve_runtime() {
  # $1 = リポジトリ root（hashFiles の評価対象）
  if [[ -f "$1/${GUARD_REL}" ]]; then
    printf '.'
  else
    printf '.vibehawk-runtime'
  fi
}

CLASSIFY_REL="scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh"
SOURCE_CLASSIFY="${REPO_ROOT}/${CLASSIFY_REL}"

echo "=== 外部リポジトリ相当 skip-mark 実行系検証（Issue #350） ==="

if [[ ! -f "$SOURCE_CLASSIFY" ]]; then
  fail "classify-paths-ignore.sh がリポジトリ本体に存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# 外部リポジトリ相当のワークスペースを作る（scripts/ci/ は持たない）。
EXTERNAL_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vibehawk-ext-repo.XXXXXX")"
cleanup() {
  rm -rf "$EXTERNAL_ROOT" || true
}
trap cleanup EXIT

# 検証 1: 外部リポジトリではランタイムが .vibehawk-runtime に解決される。
external_resolved="$(resolve_runtime "$EXTERNAL_ROOT")"
if [[ "$external_resolved" == ".vibehawk-runtime" ]]; then
  pass "外部リポジトリ（guard 不在）でランタイムが .vibehawk-runtime に解決される"
else
  fail "外部リポジトリでの解決結果が不正（${external_resolved}）"
fi

# 検証 2: 自リポジトリ（guard 実在）ではランタイムが . に解決される。
self_resolved="$(resolve_runtime "$REPO_ROOT")"
if [[ "$self_resolved" == "." ]]; then
  pass "自リポジトリ（guard 実在）でランタイムが . に解決される"
else
  fail "自リポジトリでの解決結果が不正（${self_resolved}）"
fi

# 2nd checkout が .vibehawk-runtime/ に vibehawk 本体スクリプトを展開した状態を再現する。
RUNTIME_DIR="${EXTERNAL_ROOT}/.vibehawk-runtime/scripts/ci/vibehawk-review-skip-mark"
mkdir -p "$RUNTIME_DIR"
cp "$SOURCE_CLASSIFY" "${RUNTIME_DIR}/classify-paths-ignore.sh"

# 検証 3: 外部リポジトリで lockfile のみ変更の PR が ${VIBEHAWK_RUNTIME}/ prefix 経由で
#         file not found なしに実行でき、is_skip=true を返す（merge gate 通過）。
CHANGED_FILES="${EXTERNAL_ROOT}/changed_files.txt"
GITHUB_OUTPUT_FILE="${EXTERNAL_ROOT}/github_output"
printf '%s\n' "package-lock.json" > "$CHANGED_FILES"
: > "$GITHUB_OUTPUT_FILE"

# workflow の run: 行と同じ形（cd <external> して ${VIBEHAWK_RUNTIME}/ prefix で実行）を再現する。
set +e
classify_out="$(
  cd "$EXTERNAL_ROOT" \
    && VIBEHAWK_RUNTIME="$external_resolved" \
       FILE_COUNT=1 \
       GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
       CHANGED_FILES="$CHANGED_FILES" \
       bash "${external_resolved}/scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh" 2>&1
)"
classify_code=$?
set -e

if [[ $classify_code -eq 0 ]]; then
  pass "外部リポジトリで prefix 経由の classify が file not found なしに実行できる（exit 0）"
else
  fail "外部リポジトリで classify が失敗した（exit=${classify_code}, out='${classify_out}'）"
fi

ext_is_skip="$(grep -E '^is_skip=' "$GITHUB_OUTPUT_FILE" | tail -1 | cut -d= -f2)"
if [[ "$ext_is_skip" == "true" ]]; then
  pass "外部リポジトリの lockfile-only PR で is_skip=true（required check vibehawk が success post 対象になる）"
else
  fail "外部リポジトリの lockfile-only PR で is_skip=${ext_is_skip}（true 期待）"
fi

# 検証 4: コード変更を含む PR では is_skip=false（誤通過しない）。
printf '%s\n' "package-lock.json" "src/index.ts" > "$CHANGED_FILES"
: > "$GITHUB_OUTPUT_FILE"
set +e
(
  cd "$EXTERNAL_ROOT" \
    && VIBEHAWK_RUNTIME="$external_resolved" \
       FILE_COUNT=2 \
       GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" \
       CHANGED_FILES="$CHANGED_FILES" \
       bash "${external_resolved}/scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh" >/dev/null 2>&1
)
set -e
ext_is_skip_code="$(grep -E '^is_skip=' "$GITHUB_OUTPUT_FILE" | tail -1 | cut -d= -f2)"
if [[ "$ext_is_skip_code" == "false" ]]; then
  pass "外部リポジトリで lock + コード混在 PR は is_skip=false（merge gate 誤通過なし）"
else
  fail "外部リポジトリで lock + コード混在 PR が is_skip=${ext_is_skip_code}（false 期待）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
