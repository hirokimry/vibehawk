#!/usr/bin/env bash
# 用途: test.yml の全 matrix ジョブ成功確認ステップ（Branch Protection required check 用）（Issue #179）
#
# cancelled は別 push の concurrency キャンセルによる正常終了扱い。それ以外は fail。

set -euo pipefail

: "${MATRIX_RESULT:?MATRIX_RESULT is required}"

if [ "$MATRIX_RESULT" = "success" ] || [ "$MATRIX_RESULT" = "cancelled" ]; then
  echo "test-matrix: $MATRIX_RESULT"
  exit 0
fi
echo "test-matrix が失敗しました: $MATRIX_RESULT"
exit 1
