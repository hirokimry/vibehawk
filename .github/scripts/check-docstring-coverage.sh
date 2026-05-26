#!/usr/bin/env bash
# 用途: vibehawk Pre-merge checks の Docstring Coverage（Issue #229）
#
# 入力（環境変数）:
#   GITHUB_OUTPUT   GitHub Actions step output ファイルパス（必須）
#
# 出力（GITHUB_OUTPUT に書き込み）:
#   docstring_check_status        skipped（v1 では常に skipped、言語別ツール統合は別 Issue）
#   docstring_check_explanation   理由（1 文）
#
# 設計判断:
#   docstring カバレッジ計測は言語別ツール (pydocstyle / eslint-plugin-jsdoc 等) との統合が必要。
#   v1 では言語不問で skipped を出力し、別 Issue で言語別ロジックを追加する余地を残す。

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT must be set}"

{
  printf 'docstring_check_status=%s\n' "skipped"
  printf 'docstring_check_explanation=%s\n' "Docstring coverage 計測は言語別ツール統合が必要 (別 Issue で対応)"
} >> "$GITHUB_OUTPUT"
