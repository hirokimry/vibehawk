#!/usr/bin/env bash
# 用途: release tag と package.json version の整合を確認する（Issue #179）
#
# tag（例 `v1.2.3`）の先頭 `v` を除いた値が package.json version と
# 一致しない場合は ::error:: を出力して終了コード 1 で止める。
#
# tag の取得元:
#   - RELEASE_TAG（明示渡し）を最優先する。
#     workflow_dispatch 経路では GITHUB_REF_NAME が dispatch 元ブランチ（main）になり
#     tag を取り違えるため、release.yml から tag を明示渡しする（Issue #333）。
#   - 未設定なら GITHUB_REF_NAME にフォールバックする（release: published 経路の後方互換）。

set -euo pipefail

tag_name="${RELEASE_TAG:-${GITHUB_REF_NAME:-}}"
: "${tag_name:?RELEASE_TAG or GITHUB_REF_NAME is required}"

tag_version="${tag_name#v}"
pkg_version="$(node -p 'require("./package.json").version')"
if [ "$tag_version" != "$pkg_version" ]; then
  echo "::error::tag ($tag_version) と package.json version ($pkg_version) が不一致"
  exit 1
fi
echo "tag と version の整合確認 OK: $tag_version"
