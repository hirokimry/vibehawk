#!/usr/bin/env bash
# Issue #308 — .github/scripts/version-bump-check.sh の単体テスト
#
# 一時 git リポジトリを作り base/head コミットを構成して、製品ソース変更 × version bump の
# 組み合わせごとに検査スクリプトの終了コードを検証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/.github/scripts/version-bump-check.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

if [[ ! -f "${SCRIPT}" ]]; then
  fail "version-bump-check.sh が存在しない"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

TMPDIR_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "${TMPDIR_ROOT}" || true
}
trap cleanup EXIT

# 機能: 一時リポジトリで base→head を構成し、検査スクリプトの exit code を返す
# 引数: <base_version> <head_version> <head_change_kind>
#   head_change_kind: source（cli/ を変更） / plugin（plugin.json のみ変更） / none（変更なし）
run_case() {
  local base_version="$1"
  local head_version="$2"
  local change_kind="$3"
  local dir
  dir="$(mktemp -d "${TMPDIR_ROOT}/repo.XXXXXX")"

  git -C "${dir}" init -q
  git -C "${dir}" config user.email "test@example.com"
  git -C "${dir}" config user.name "test"

  mkdir -p "${dir}/cli" "${dir}/.claude-plugin"
  printf '{\n  "version": "%s"\n}\n' "${base_version}" > "${dir}/package.json"
  printf 'console.log("base");\n' > "${dir}/cli/index.js"
  printf '{\n  "version": "0.1.0"\n}\n' > "${dir}/.claude-plugin/plugin.json"
  git -C "${dir}" add -A
  git -C "${dir}" commit -q -m "base"

  printf '{\n  "version": "%s"\n}\n' "${head_version}" > "${dir}/package.json"
  case "${change_kind}" in
    source)
      printf 'console.log("head");\n' > "${dir}/cli/index.js"
      ;;
    plugin)
      printf '{\n  "version": "0.2.0"\n}\n' > "${dir}/.claude-plugin/plugin.json"
      ;;
    none)
      :
      ;;
  esac
  git -C "${dir}" add -A
  git -C "${dir}" commit -q -m "head" --allow-empty

  local code=0
  ( cd "${dir}" && bash "${SCRIPT}" "HEAD~1" "HEAD" >/dev/null 2>&1 ) || code=$?
  echo "${code}"
}

echo "Case 1: 製品ソース変更 + version 据え置き → 1（警告）"
code="$(run_case "0.1.0" "0.1.0" source)"
if [[ "${code}" == "1" ]]; then pass "Case 1"; else fail "Case 1: code=${code}"; fi

echo "Case 2: 製品ソース変更 + version bump → 0"
code="$(run_case "0.1.0" "0.2.0" source)"
if [[ "${code}" == "0" ]]; then pass "Case 2"; else fail "Case 2: code=${code}"; fi

echo "Case 3: plugin.json のみ変更（製品ソース無変更） → 0（監視対象外）"
code="$(run_case "0.1.0" "0.1.0" plugin)"
if [[ "${code}" == "0" ]]; then pass "Case 3"; else fail "Case 3: code=${code}"; fi

echo "Case 4: 製品ソース無変更（version も据え置き） → 0"
code="$(run_case "0.1.0" "0.1.0" none)"
if [[ "${code}" == "0" ]]; then pass "Case 4"; else fail "Case 4: code=${code}"; fi

echo "Case 5: package.json のみ version bump（製品ソース扱いで検知 → bump 済み） → 0"
code="$(run_case "0.1.0" "0.2.0" none)"
if [[ "${code}" == "0" ]]; then pass "Case 5"; else fail "Case 5: code=${code}"; fi

echo "Case 6: 引数不足 → 2"
code=0
bash "${SCRIPT}" "HEAD" >/dev/null 2>&1 || code=$?
if [[ "${code}" == "2" ]]; then pass "Case 6"; else fail "Case 6: code=${code}"; fi

echo "==="
echo "passed: ${PASSED}, failed: ${FAILED}"
exit "${FAILED}"
