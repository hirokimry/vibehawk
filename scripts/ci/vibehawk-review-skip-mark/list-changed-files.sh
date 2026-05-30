#!/usr/bin/env bash
# 用途: vibehawk-review-skip-mark.yml の変更ファイル一覧取得ステップ本体（Issue #178）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/gh-helpers.sh
. "${SCRIPT_DIR}/../common/gh-helpers.sh"

: "${PR_NUMBER:?PR_NUMBER が必須です}"
: "${REPO:?REPO が必須です}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT が必須です}"

gh_api_paginated "/repos/${REPO}/pulls/${PR_NUMBER}/files" '.[].filename' > changed_files.txt
file_count=$(wc -l < changed_files.txt | tr -d ' ')
echo "count=${file_count}" >> "$GITHUB_OUTPUT"
echo "変更ファイル数: ${file_count}"
cat changed_files.txt
