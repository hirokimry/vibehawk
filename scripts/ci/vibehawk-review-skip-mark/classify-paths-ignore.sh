#!/usr/bin/env bash
# 用途: vibehawk-review-skip-mark.yml の paths-ignore 全マッチ判定ステップ本体（Issue #178）
#
# 保守注意: 下記 case 文は vibehawk-review.yml の paths-ignore リストと完全に同期させること。
# リスト変更時は本ファイル・.github/workflows/振り先・tests/test_workflow_skip_mark.sh の
# 3 箇所を同時更新する。同期忘れの失敗モードは「PR が BLOCKED」方向のみで、merge gate 誤通過は構造上発生しない。

set -euo pipefail

: "${FILE_COUNT:?FILE_COUNT が必須です}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT が必須です}"
CHANGED_FILES_PATH="${CHANGED_FILES:-changed_files.txt}"

all_match=true
if [ "${FILE_COUNT}" -eq 0 ]; then
  # 変更ゼロは判定不能のため安全側（skip しない）に倒す
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
