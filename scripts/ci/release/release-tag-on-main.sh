#!/usr/bin/env bash
# 用途: main への push 時に package.json の version が新規なら tag + GitHub Release を作成する
#       （Issue #307, Option B）。
#
# 設計:
#   - branch protection（require_pr + enforce_admins）で main への直接 commit は不可。
#     本スクリプトは tag と GitHub Release の作成のみ行い、branch ref には一切触れない。
#   - Release 作成後、release.yml（npm publish）を workflow_dispatch で起動する（Issue #333）。
#     GITHUB_TOKEN が作成した Release は release: published を発火させない（GitHub 公式仕様。
#     GITHUB_TOKEN 由来イベントは workflow_dispatch / repository_dispatch を除き新しい workflow を
#     起こさない）ため、gh workflow run で明示的に publish を繋ぐ。
#   - 事故防止: push の前後（BEFORE_SHA → AFTER_SHA）で version が変化した時だけ Release を作る。
#     version 据え置きの push（通常の機能 PR マージ等）では何もしない。
#
# 環境変数:
#   AFTER_SHA  : push 後 SHA（= 現在の HEAD、必須）
#   BEFORE_SHA : push 前 SHA（github.event.before。初回 push 等で不明なら空でも可）
#   GH_TOKEN   : gh CLI 用トークン

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/log.sh
. "${SCRIPT_DIR}/../common/log.sh"
# shellcheck source=./cc-analyze.sh
. "${SCRIPT_DIR}/cc-analyze.sh"

read_version_at() {
  # 指定 ref の package.json から version を読む（読めなければ空文字）。
  # version-bump-check.sh（Issue #308）と解析方式を jq に統一する（Issue #315）。
  local ref="$1" blob
  blob="$(git show "${ref}:package.json" 2> /dev/null || true)"
  if [[ -z "$blob" ]]; then
    printf ''
    return 0
  fi
  # jq が失敗（不正 JSON 等）しても set -e で abort せず空文字に倒す（Issue #317）。
  printf '%s' "$blob" | jq -r '.version // ""' 2> /dev/null || true
}

main() {
  : "${AFTER_SHA:?AFTER_SHA is required}"
  if ! command -v jq > /dev/null 2>&1; then
    log_error "jq が必要です"
    return 2
  fi
  local before="${BEFORE_SHA:-}"

  # jq が失敗しても abort せず空文字に倒し、version 不明時は graceful skip する（Issue #317、bad tag 防止）。
  local ver_after
  ver_after="$(jq -r '.version // ""' package.json 2> /dev/null || true)"
  if [[ -z "$ver_after" ]]; then
    log_info "package.json から version を取得できないため Release 作成をスキップします"
    return 0
  fi

  # 直前の version を特定する。all-zero SHA（初回 push）や読み取り不能時は空。
  local ver_before=""
  if [[ -n "$before" && ! "$before" =~ ^0+$ ]]; then
    ver_before="$(read_version_at "$before")"
  fi

  if [[ -z "$ver_before" ]]; then
    log_info "直前の version を特定できないため Release 作成をスキップします（before=${before:-none}）"
    return 0
  fi

  if [[ "$ver_before" == "$ver_after" ]]; then
    log_info "version 変化なし（${ver_after}）。Release 作成をスキップします"
    return 0
  fi

  local tag="v${ver_after}"
  if git rev-parse -q --verify "refs/tags/${tag}" > /dev/null 2>&1; then
    log_info "tag ${tag} は既に存在します。スキップします"
    return 0
  fi
  if gh release view "$tag" > /dev/null 2>&1; then
    log_info "GitHub Release ${tag} は既に存在します。スキップします"
    return 0
  fi

  cc_analyze "${before}..${AFTER_SHA}"
  local notes="$CC_RELEASE_NOTES"
  if [[ -z "$notes" ]]; then
    notes="バージョン ${ver_after} をリリースしました。"
  fi

  log_info "Release ${tag} を作成します（${ver_before} → ${ver_after}）"
  gh release create "$tag" --title "$tag" --notes "$notes" --target "$AFTER_SHA"
  log_info "Release ${tag} を作成しました"

  # GITHUB_TOKEN 製 Release は release: published を発火させないため、publish を明示起動する（Issue #333）
  log_info "release.yml（npm publish）を tag ${tag} で起動します"
  gh workflow run release.yml -f tag="$tag"
  log_info "release.yml を起動しました"
}

main "$@"
