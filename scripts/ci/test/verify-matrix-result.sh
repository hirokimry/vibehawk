#!/usr/bin/env bash
# scripts/ci/test/verify-matrix-result.sh
#
# test workflow（`.github/workflows/test.yml`）の "全 matrix ジョブの成功を確認"
# ステップ。Branch Protection の required check として機能する集約ジョブ用。
#
# `test-matrix` ジョブの `needs.test-matrix.result` を環境変数 `MATRIX_RESULT`
# で受け取り、`success` または `cancelled` なら 0 で抜ける（cancelled は別 push の
# concurrency キャンセル等で正常扱い）。それ以外なら 1 で fail。
#
# 切り出し元: test.yml の "全 matrix ジョブの成功を確認" ステップ（Issue #179）。
#
# 使用例（workflow から）:
#   - name: 全 matrix ジョブの成功を確認
#     env:
#       MATRIX_RESULT: ${{ needs.test-matrix.result }}
#     run: bash scripts/ci/test/verify-matrix-result.sh
#
# 入力:
#   - MATRIX_RESULT: 集約対象ジョブの result（`success` / `failure` /
#     `cancelled` / `skipped`）
# 出力:
#   - 成功時: stdout に "test-matrix: <result>"
#   - 失敗時: stdout に "test-matrix が失敗しました: <result>" + 終了コード 1

set -euo pipefail

: "${MATRIX_RESULT:?MATRIX_RESULT is required}"

if [ "$MATRIX_RESULT" = "success" ] || [ "$MATRIX_RESULT" = "cancelled" ]; then
  echo "test-matrix: $MATRIX_RESULT"
  exit 0
fi
echo "test-matrix が失敗しました: $MATRIX_RESULT"
exit 1
