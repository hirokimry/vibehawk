#!/usr/bin/env bash
# 用途: リリース PR 内で実行し、Conventional Commits からバージョンを決定して
#       package.json + CHANGELOG.md を更新する（Issue #307, Option B）。
#
# なぜ CI ではなくリリース PR 内で実行するか:
#   main は branch protection（require_pr + enforce_admins）により CI からの直接 commit が
#   不可能。そのため version の bump は「リリース PR の差分」として人手のレビューを通す。
#   /vibecorp:release-epic などリリース PR を作る側がこのスクリプトを呼ぶ。
#
# 使い方:
#   scripts/ci/release/prepare-release.sh [BASE_REF]
#     BASE_REF 省略時は直近 tag を、tag が無ければ全履歴を解析対象にする。
#
# 出力:
#   bump が発生した場合は新バージョン文字列を stdout に出力する。
#   リリース対象（feat/fix/perf/breaking）が無い場合は何も変更せず exit 0。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/log.sh
. "${SCRIPT_DIR}/../common/log.sh"
# shellcheck source=./cc-analyze.sh
. "${SCRIPT_DIR}/cc-analyze.sh"
# 実行中のリポジトリのルート（リリース PR の checkout 先 / テスト用の一時リポジトリ）を対象にする。
REPO_ROOT="$(git rev-parse --show-toplevel)"

update_changelog() {
  local version="$1"
  local changelog="${REPO_ROOT}/CHANGELOG.md"
  if [[ ! -f "$changelog" ]]; then
    log_warn "CHANGELOG.md が無いため追記をスキップします"
    return 0
  fi

  local today secfile tmp
  today="$(date +%Y-%m-%d)"

  # 改行を含むセクションを awk -v で渡すと BSD awk が落ちるため一時ファイル経由で渡す（shell.md 互換）。
  secfile="$(mktemp "$(dirname "$changelog")/.CHANGELOG-sec.XXXXXX")"
  {
    printf '## v%s - %s\n\n' "$version" "$today"
    printf '%s' "$CC_RELEASE_NOTES"
  } > "$secfile"

  # 先頭の `## v<数字>` 見出しの直前に新セクションを挿入する（既存履歴を壊さない）。
  tmp="$(mktemp "$(dirname "$changelog")/.CHANGELOG.XXXXXX")"
  awk -v secfile="$secfile" '
    function emit(  line) { while ((getline line < secfile) > 0) print line; close(secfile) }
    BEGIN { inserted = 0 }
    /^## v[0-9]/ && inserted == 0 { emit(); inserted = 1 }
    { print }
    END { if (inserted == 0) emit() }
  ' "$changelog" > "$tmp" && mv "$tmp" "$changelog"
  rm -f "$secfile"
}

main() {
  local base="${1:-}"
  if [[ -z "$base" ]]; then
    base="$(git describe --tags --abbrev=0 2> /dev/null || true)"
  fi

  local range
  if [[ -z "$base" ]]; then
    range="HEAD"
  else
    range="${base}..HEAD"
  fi

  cc_analyze "$range"

  if [[ "$CC_BUMP_LEVEL" -eq 0 ]]; then
    # stdout は新バージョン出力専用なので進捗は stderr に出す
    log_info "リリース対象の変更（feat/fix/perf/breaking）がないため bump をスキップします" >&2
    return 0
  fi

  local cur new
  cur="$(cd "$REPO_ROOT" && node -p 'require("./package.json").version')"
  new="$(bump_version "$cur" "$CC_BUMP_LEVEL")"
  # stdout は新バージョン出力専用なので進捗は stderr に出す
  log_info "現行バージョン ${cur} → 新バージョン ${new}（bump level ${CC_BUMP_LEVEL}）" >&2

  # package.json + package-lock.json の version を更新する（git tag/commit は作らない）。
  ( cd "$REPO_ROOT" && npm version "$new" --no-git-tag-version --allow-same-version > /dev/null )

  update_changelog "$new"

  printf '%s\n' "$new"
}

main "$@"
