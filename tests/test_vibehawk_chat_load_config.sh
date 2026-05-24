#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/load-config.sh 単体テスト（Issue #177）
#
# .vibehawk.yaml の language キー読み取りと "en" フォールバックを検証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/load-config.sh"

PASSED=0
FAILED=0

pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/vibehawk-chat/load-config.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "load-config.sh が存在する"
else
  fail "load-config.sh が存在しない"
  exit 1
fi

# 前提: python3 + yaml + jq が必要。なければ skip（CI には揃っている前提）
if ! command -v python3 > /dev/null 2>&1; then
  echo "  ⚠ python3 が見つからない → スキップ"
  echo "=== 結果: $PASSED passed, $FAILED failed (skipped) ==="
  exit 0
fi
if ! python3 -c "import yaml" > /dev/null 2>&1; then
  echo "  ⚠ pyyaml が見つからない → スキップ（CI では pip install --user で導入される）"
  echo "=== 結果: $PASSED passed, $FAILED failed (skipped) ==="
  exit 0
fi
if ! command -v jq > /dev/null 2>&1; then
  echo "  ⚠ jq が見つからない → スキップ"
  echo "=== 結果: $PASSED passed, $FAILED failed (skipped) ==="
  exit 0
fi

# テスト用のサンドボックスディレクトリで実行（CWD を切り替えて .vibehawk.yaml の有無を制御）
SANDBOX="$(mktemp -d)"
GITHUB_OUTPUT_FILE="$(mktemp)"
trap 'rm -rf "$SANDBOX" "$GITHUB_OUTPUT_FILE"' EXIT

(
  cd "$SANDBOX"
  : > "$GITHUB_OUTPUT_FILE"
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" bash "$SCRIPT" > /dev/null
)
if grep -Fxq "language=en" "$GITHUB_OUTPUT_FILE"; then
  pass ".vibehawk.yaml 不在 → language=en（フォールバック）"
else
  fail ".vibehawk.yaml 不在時の出力が想定と異なる: $(tr '\n' '|' < "$GITHUB_OUTPUT_FILE")"
fi

(
  cd "$SANDBOX"
  cat > .vibehawk.yaml <<'EOF'
language: ja
EOF
  : > "$GITHUB_OUTPUT_FILE"
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" bash "$SCRIPT" > /dev/null
)
if grep -Fxq "language=ja" "$GITHUB_OUTPUT_FILE"; then
  pass ".vibehawk.yaml に language: ja → language=ja"
else
  fail ".vibehawk.yaml に language: ja 設定時の出力が想定と異なる: $(tr '\n' '|' < "$GITHUB_OUTPUT_FILE")"
fi

(
  cd "$SANDBOX"
  : > .vibehawk.yaml
  : > "$GITHUB_OUTPUT_FILE"
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" bash "$SCRIPT" > /dev/null
)
if grep -Fxq "language=en" "$GITHUB_OUTPUT_FILE"; then
  pass ".vibehawk.yaml が空 → language=en（jq // \"en\" フォールバック）"
else
  fail "空 yaml 時の出力が想定と異なる: $(tr '\n' '|' < "$GITHUB_OUTPUT_FILE")"
fi

(
  cd "$SANDBOX"
  cat > .vibehawk.yaml <<'EOF'
other_key: value
EOF
  : > "$GITHUB_OUTPUT_FILE"
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" bash "$SCRIPT" > /dev/null
)
if grep -Fxq "language=en" "$GITHUB_OUTPUT_FILE"; then
  pass ".vibehawk.yaml に language キーなし → language=en"
else
  fail "language キー不在時の出力が想定と異なる: $(tr '\n' '|' < "$GITHUB_OUTPUT_FILE")"
fi

(
  cd "$SANDBOX"
  rm -f .vibehawk.yaml
  cat > .coderabbit.yaml <<'EOF'
language: ja
EOF
  : > "$GITHUB_OUTPUT_FILE"
  GITHUB_OUTPUT="$GITHUB_OUTPUT_FILE" bash "$SCRIPT" > /dev/null
)
if grep -Fxq "language=en" "$GITHUB_OUTPUT_FILE"; then
  pass ".coderabbit.yaml は読まれない（Issue #172 fallback 撤廃、en フォールバック）"
else
  fail ".coderabbit.yaml fallback が混入している: $(tr '\n' '|' < "$GITHUB_OUTPUT_FILE")"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
