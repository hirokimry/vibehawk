#!/usr/bin/env bash
# 用途: package.json version の bump 漏れを検知する（Issue #308）
#
# vibehawk 製品ソース（cli/ / templates/ / package.json）が変更された PR で
# package.json の version が据え置きの場合に警告する。npm publish 対象の取りこぼし防止。
# .claude-plugin/plugin.json は vendored 開発ツールでありリリース対象外のため監視しない（Issue #306）。
#
# 使い方:
#   bash .github/scripts/version-bump-check.sh <BASE_REF> <HEAD_REF>
#
# 終了コード:
#   0 — 問題なし（製品ソース無変更、または製品ソース変更ありかつ version bump あり、または前提不足で skip）
#   1 — 警告（製品ソース変更ありかつ package.json version 据え置き）
#   2 — 引数不足・前提コマンド不在等のエラー

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "使い方: bash .github/scripts/version-bump-check.sh <BASE_REF> <HEAD_REF>" >&2
  exit 2
fi

BASE_REF="$1"
HEAD_REF="$2"

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq が必要です" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "❌ git が必要です" >&2
  exit 2
fi

PACKAGE_PATH="package.json"

# 監視対象は package.json の files[] 相当（製品ソース）+ package.json 自身（Issue #306）。
# .claude-plugin/ は意図的に含めない。
SOURCE_PATHSPECS=("cli/" "templates/" "package.json")

# 機能: ref に当該パスが存在しない場合は空文字を返す（base / head 片側不在を許容する）
git_show_or_empty() {
  local ref="$1"
  local path="$2"
  if git cat-file -e "${ref}:${path}" 2>/dev/null; then
    git show "${ref}:${path}"
  else
    echo ""
  fi
}

# 製品ソースに base→head の差分があるかを判定する
changed_files=$(git diff --name-only "${BASE_REF}" "${HEAD_REF}" -- "${SOURCE_PATHSPECS[@]}")

if [[ -z "${changed_files}" ]]; then
  echo "✅ 製品ソース（cli/ / templates/ / package.json）に変更なし"
  exit 0
fi

base_package=$(git_show_or_empty "${BASE_REF}" "${PACKAGE_PATH}")
head_package=$(git_show_or_empty "${HEAD_REF}" "${PACKAGE_PATH}")

# package.json が片側に存在しない場合は graceful skip する
if [[ -z "${base_package}" || -z "${head_package}" ]]; then
  echo "✅ package.json が base / head のいずれかに存在しないため、チェックをスキップします"
  exit 0
fi

base_version=$(printf '%s' "${base_package}" | jq -r '.version // ""')
head_version=$(printf '%s' "${head_package}" | jq -r '.version // ""')

if [[ -z "${base_version}" || -z "${head_version}" ]]; then
  echo "✅ package.json に version フィールドが見つからないため、チェックをスキップします"
  exit 0
fi

if [[ "${base_version}" != "${head_version}" ]]; then
  echo "✅ 製品ソース変更ありかつ package.json version が ${base_version} → ${head_version} に bump 済み"
  exit 0
fi

{
  echo "⚠️ 製品ソース（cli/ / templates/ / package.json）が変更されていますが、package.json の version (${base_version}) が bump されていません。"
  echo "   npm publish 対象の取りこぼしを防ぐため、package.json の version を更新してください。"
} >&2
exit 1
