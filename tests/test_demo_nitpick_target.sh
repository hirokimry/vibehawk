#!/usr/bin/env bash
# demo-nitpick-target.sh のテスト（#282 デモ、マージしない）
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
out="$(bash "${REPO_ROOT}/.github/scripts/demo-nitpick-target.sh" 2 3)"
if [[ "$out" == "5" ]]; then
  echo "  ✓ 2 + 3 = 5"
else
  echo "  ✗ 期待 5 だが ${out}"
  exit 1
fi
echo "=== 結果: 1 passed, 0 failed ==="
