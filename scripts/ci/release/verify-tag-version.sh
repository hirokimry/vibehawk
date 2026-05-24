#!/usr/bin/env bash
# 用途: release tag と package.json version の整合を確認する（Issue #179）
#
# GITHUB_REF_NAME（例 `v1.2.3`）の先頭 `v` を除いた値が package.json version と
# 一致しない場合は ::error:: を出力して終了コード 1 で止める。

set -euo pipefail

: "${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"

tag_version="${GITHUB_REF_NAME#v}"
pkg_version="$(node -p 'require("./package.json").version')"
if [ "$tag_version" != "$pkg_version" ]; then
  echo "::error::tag ($tag_version) と package.json version ($pkg_version) が不一致"
  exit 1
fi
echo "tag と version の整合確認 OK: $tag_version"
