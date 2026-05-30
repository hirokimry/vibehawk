#!/usr/bin/env bash
# 用途: test.yml の全テスト実行ステップ本体（Issue #179）
#
# 同等ロジックが scripts/ci/release/run-tests.sh にも存在するが、各 workflow の
# 責務を分離するため二重配置する（短く保ち、将来の divergence の余地を残す）。

set -euo pipefail

shopt -s nullglob
files=(tests/test_*.sh)
if [ ${#files[@]} -eq 0 ]; then
  echo "テストファイルが見つかりません"
  exit 1
fi

failed=0
for f in "${files[@]}"; do
  echo "=== $f ==="
  bash "$f" || failed=1
done
exit "$failed"
