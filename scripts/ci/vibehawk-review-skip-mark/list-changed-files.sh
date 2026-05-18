#!/usr/bin/env bash
# scripts/ci/vibehawk-review-skip-mark/list-changed-files.sh
#
# vibehawk-review-skip-mark.yml の step「変更ファイル一覧の取得」相当。
# PR の全変更ファイルパスを 1 行 1 ファイルで取得し、件数を $GITHUB_OUTPUT に書く。
#
# 入力（環境変数）:
#   GH_TOKEN       — gh CLI 認証用（gh CLI が直接読む）
#   PR_NUMBER      — 取得対象の PR 番号
#   REPO           — owner/repo 形式（例: hirokimry/vibehawk）
#   GITHUB_OUTPUT  — GitHub Actions 出力ファイルパス（CI では自動設定）
#
# 副作用:
#   - cwd に changed_files.txt を作成（1 行 1 ファイルパス）
#   - $GITHUB_OUTPUT に `count=<N>` を追記
#   - stdout に件数と変更ファイル一覧を表示
#
# Issue #178（エピック #174）で vibehawk-review-skip-mark.yml から切り出された。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/gh-helpers.sh
. "${SCRIPT_DIR}/../common/gh-helpers.sh"

: "${PR_NUMBER:?PR_NUMBER が必須です}"
: "${REPO:?REPO が必須です}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT が必須です}"

# PR の全変更ファイルパスを 1 行 1 ファイルで取得
gh_api_paginated "/repos/${REPO}/pulls/${PR_NUMBER}/files" '.[].filename' > changed_files.txt
file_count=$(wc -l < changed_files.txt | tr -d ' ')
echo "count=${file_count}" >> "$GITHUB_OUTPUT"
echo "変更ファイル数: ${file_count}"
cat changed_files.txt
