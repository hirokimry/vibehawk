#!/usr/bin/env bash
# scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh
#
# vibehawk-review-skip-mark.yml の step「paths-ignore 全マッチ判定」相当。
# 変更ファイル一覧が vibehawk-review.yml の paths-ignore に全マッチするかを判定する。
#
# 同期必須（保守者向け）:
#   下記 case 文は `vibehawk-review.yml` の `paths-ignore` リストと完全に同期させること。
#   `vibehawk-review.yml` のリストを編集した場合、以下 3 箇所を手動で同時更新する必要がある:
#     1. templates/.github/workflows/vibehawk-review-skip-mark.yml が呼び出すスクリプト（本ファイル）
#     2. .github/workflows/vibehawk-review-skip-mark.yml が呼び出すスクリプト（同上、共有）
#     3. tests/test_workflow_skip_mark.sh のパターン一覧
#   同期忘れの失敗モードは常に「PR が BLOCKED」方向のみで、merge gate 誤通過は構造上発生しない。
#
# 入力（環境変数）:
#   FILE_COUNT     — 変更ファイル数（前ステップ list-changed-files.sh の出力）
#   GITHUB_OUTPUT  — GitHub Actions 出力ファイルパス（CI では自動設定）
#   CHANGED_FILES  — 変更ファイル一覧パス（省略時 changed_files.txt、tests 用）
#
# 副作用:
#   - $GITHUB_OUTPUT に `is_skip=true|false` を追記
#   - stdout に判定結果を表示
#
# Issue #178（エピック #174）で vibehawk-review-skip-mark.yml から切り出された。

set -euo pipefail

: "${FILE_COUNT:?FILE_COUNT が必須です}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT が必須です}"
CHANGED_FILES_PATH="${CHANGED_FILES:-changed_files.txt}"

all_match=true
if [ "${FILE_COUNT}" -eq 0 ]; then
  # ファイル変更ゼロは判定不能のため安全側で skip post を行わない
  all_match=false
fi
while IFS= read -r file; do
  [ -z "$file" ] && continue
  case "$file" in
    .github/dependabot.yml) ;;
    package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lockb) ;;
    *) all_match=false; break ;;
  esac
done < "$CHANGED_FILES_PATH"
echo "is_skip=${all_match}" >> "$GITHUB_OUTPUT"
echo "paths-ignore 全マッチ: ${all_match}"
