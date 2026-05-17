#!/usr/bin/env bash
# scripts/ci/release/verify-tag-version.sh
#
# release workflow（`.github/workflows/release.yml`）の "tag と package.json
# version の整合確認" ステップ。
#
# GitHub Release の tag（`GITHUB_REF_NAME`、例 `v1.2.3`）から先頭 `v` を除いた
# バージョン文字列が `package.json` の `version` フィールドと一致することを検証する。
# 不一致なら `::error::` 形式で GitHub Actions ログに出力し、終了コード 1 で終わる。
#
# 切り出し元: release.yml の "tag と package.json version の整合確認" ステップ
# （Issue #179）。
#
# 使用例（workflow から）:
#   - name: tag と package.json version の整合確認
#     run: bash scripts/ci/release/verify-tag-version.sh
#
# 入力:
#   - GITHUB_REF_NAME: GitHub Release の tag 名（例 `v1.2.3`）
# 出力:
#   - 成功時: stdout に "tag と version の整合確認 OK: <version>"
#   - 失敗時: stdout に "::error::tag (<a>) と package.json version (<b>) が不一致"
#     + 終了コード 1

set -euo pipefail

: "${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"

tag_version="${GITHUB_REF_NAME#v}"
pkg_version="$(node -p 'require("./package.json").version')"
if [ "$tag_version" != "$pkg_version" ]; then
  echo "::error::tag ($tag_version) と package.json version ($pkg_version) が不一致"
  exit 1
fi
echo "tag と version の整合確認 OK: $tag_version"
