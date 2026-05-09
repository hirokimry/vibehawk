#!/usr/bin/env bash
# Issue #10: vibehawk-review.yml の vibehawk_config ステップで使う
# YAML パーサ（Python + PyYAML → JSON 変換 → jq）の単体テスト

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0
SKIPPED=0

pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  FAILED=$((FAILED + 1))
}

skip() {
  echo "  ⊘ $1"
  SKIPPED=$((SKIPPED + 1))
}

# PyYAML 可用性チェック（ubuntu-latest はプリインストール、ローカル macOS はなしの場合あり）
if ! python3 -c "import yaml" 2>/dev/null; then
  echo "=== PyYAML 未インストール → 全テストスキップ（GitHub Actions runner では pip フォールバックで動作） ==="
  echo "  ⊘ ローカル環境スキップ（CI ubuntu-latest では pyyaml プリインストール、不在時は pip install --user --quiet pyyaml が workflow 側で実行される）"
  SKIPPED=$((SKIPPED + 1))
  echo "=== 結果: $PASSED passed, $FAILED failed, $SKIPPED skipped ==="
  exit 0
fi

# 一時ディレクトリで .vibehawk.yaml を作成してパース検証
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# パース関数（vibehawk_config ステップと同等のロジック）
parse_yaml() {
  local file="$1"
  python3 -c "import yaml,json; print(json.dumps(yaml.safe_load(open('$file')) or {}))"
}

echo "=== .vibehawk.yaml フルスキーマパース ==="

cat > "$TMPDIR/.vibehawk.yaml" <<'EOF'
reviews:
  path_filters:
    - "node_modules/**"
    - "dist/**"
  path_instructions:
    - path: "src/auth/**"
      instructions: "認証フローの観点で見て"
  size_limits:
    full_review_files: 30
    focused_review_files: 80
    skip_inline_files: 3000
language: ja
EOF

config_json="$(parse_yaml "$TMPDIR/.vibehawk.yaml")"

# language: ja
language="$(echo "$config_json" | jq -r '.language // "en"')"
if [[ "$language" == "ja" ]]; then
  pass "language: ja が抽出される"
else
  fail "language が想定と異なる: '$language'"
fi

# size_limits 3 値
for key in full_review_files focused_review_files skip_inline_files; do
  expected="$(echo "$config_json" | jq -r ".reviews.size_limits.$key")"
  case "$key" in
    full_review_files) want=30 ;;
    focused_review_files) want=80 ;;
    skip_inline_files) want=3000 ;;
  esac
  if [[ "$expected" == "$want" ]]; then
    pass "size_limits.$key=$want が抽出される"
  else
    fail "size_limits.$key が想定と異なる: '$expected' (期待: $want)"
  fi
done

# path_filters
filters="$(echo "$config_json" | jq -c '.reviews.path_filters')"
if [[ "$filters" == '["node_modules/**","dist/**"]' ]]; then
  pass "path_filters が JSON 配列として抽出される"
else
  fail "path_filters の抽出結果が想定と異なる: '$filters'"
fi

# path_instructions
instructions="$(echo "$config_json" | jq -c '.reviews.path_instructions')"
if [[ "$instructions" == '[{"path":"src/auth/**","instructions":"認証フローの観点で見て"}]' ]]; then
  pass "path_instructions が JSON 配列として抽出される"
else
  fail "path_instructions の抽出結果が想定と異なる: '$instructions'"
fi

echo "=== 空の .vibehawk.yaml デフォルト値フォールバック ==="

cat > "$TMPDIR/empty.yaml" <<'EOF'
EOF

empty_json="$(parse_yaml "$TMPDIR/empty.yaml")"
if [[ "$empty_json" == "{}" ]]; then
  pass "空 YAML が {} としてパースされる"
else
  fail "空 YAML のパース結果が想定と異なる: '$empty_json'"
fi

# // デフォルト値が機能する
language_default="$(echo "$empty_json" | jq -r '.language // "en"')"
full_default="$(echo "$empty_json" | jq -r '.reviews.size_limits.full_review_files // 30')"
if [[ "$language_default" == "en" ]] && [[ "$full_default" == "30" ]]; then
  pass "未設定キーは jq // でデフォルト値にフォールバック"
else
  fail "デフォルトフォールバックが機能しない: language='$language_default', full='$full_default'"
fi

echo "=== 部分設定（一部キーのみ） ==="

cat > "$TMPDIR/partial.yaml" <<'EOF'
reviews:
  path_filters:
    - "vendor/**"
language: en
EOF

partial_json="$(parse_yaml "$TMPDIR/partial.yaml")"
filters_partial="$(echo "$partial_json" | jq -c '.reviews.path_filters')"
size_default="$(echo "$partial_json" | jq -r '.reviews.size_limits.full_review_files // 30')"

if [[ "$filters_partial" == '["vendor/**"]' ]] && [[ "$size_default" == "30" ]]; then
  pass "部分設定で path_filters は反映され、size_limits はデフォルト値にフォールバック"
else
  fail "部分設定の挙動が想定と異なる: filters='$filters_partial', size='$size_default'"
fi

echo "=== 不正 YAML のエラーハンドリング ==="

cat > "$TMPDIR/invalid.yaml" <<'EOF'
this: is: invalid: yaml:
  - {{ broken
EOF

if parse_yaml "$TMPDIR/invalid.yaml" 2>/dev/null; then
  fail "不正 YAML がエラーなくパースされた（PyYAML が壊れている可能性）"
else
  pass "不正 YAML が PyYAML でエラー終了する（exit !=0）"
fi

echo "=== 結果: $PASSED passed, $FAILED failed, $SKIPPED skipped ==="
[[ $FAILED -eq 0 ]]
