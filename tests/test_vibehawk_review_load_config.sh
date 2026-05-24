#!/usr/bin/env bash
# scripts/ci/vibehawk-review/load-config.sh の単体テスト。
#
# `.vibehawk.yaml` 不在時のデフォルト値、存在時のキーマッピング、
# depth の段階的劣化（full / focused / lightweight / summary_only）を網羅する。
#
# 注意: load-config.sh は `.vibehawk.yaml` を CWD から読むため、各シナリオ
# で隔離 tempdir に cd して実行する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/load-config.sh"

PASSED=0
FAILED=0

pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  FAILED=$((FAILED + 1))
}

echo "=== scripts/ci/vibehawk-review/load-config.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "load-config.sh が存在する"
else
  fail "load-config.sh が存在しない"
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

run_in() {
  local workdir="$1" files_count="$2"
  local output_file="${TMP_ROOT}/github_output"
  : > "$output_file"
  local stdout_file="${TMP_ROOT}/stdout"
  local rc=0
  if [[ "$files_count" == "__UNSET__" ]]; then
    (
      cd "$workdir"
      env -u FILES_COUNT GITHUB_OUTPUT="$output_file" bash "$SCRIPT"
    ) > "$stdout_file" 2>&1 || rc=$?
  else
    (
      cd "$workdir"
      FILES_COUNT="$files_count" GITHUB_OUTPUT="$output_file" bash "$SCRIPT"
    ) > "$stdout_file" 2>&1 || rc=$?
  fi
  echo "$rc"
}

OUT="${TMP_ROOT}/github_output"

WORK1="${TMP_ROOT}/case1"
mkdir -p "$WORK1"
rc=$(run_in "$WORK1" 5)
if [[ "$rc" -eq 0 ]] \
   && grep -qx "config_source=default" "$OUT" \
   && grep -qx "language=en" "$OUT" \
   && grep -qx "files_count=5" "$OUT" \
   && grep -qx "depth=full" "$OUT" \
   && grep -qFx "path_filters=[]" "$OUT" \
   && grep -qFx "path_instructions=[]" "$OUT"; then
  pass ".vibehawk.yaml 不在 → デフォルト値 + depth=full"
else
  fail "デフォルトシナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

WORK2="${TMP_ROOT}/case2"
mkdir -p "$WORK2"
cat > "$WORK2/.vibehawk.yaml" <<'EOF'
language: ja
reviews:
  size_limits:
    full_review_files: 10
    focused_review_files: 50
    skip_inline_files: 1000
  path_filters:
    - "node_modules/**"
    - "dist/**"
  path_instructions:
    - path: "src/auth/**"
      instructions: "認証フロー観点で見て"
EOF

# python3 + pyyaml が利用可能か確認、なければスキップ
if python3 -c "import yaml" 2>/dev/null; then
  rc=$(run_in "$WORK2" 5)
  if [[ "$rc" -eq 0 ]] \
     && grep -qx "config_source=vibehawk" "$OUT" \
     && grep -qx "language=ja" "$OUT" \
     && grep -qx "files_count=5" "$OUT" \
     && grep -qx "depth=full" "$OUT" \
     && grep -qF 'path_filters=["node_modules/**","dist/**"]' "$OUT" \
     && grep -qF 'path_instructions=[{"path":"src/auth/**","instructions":"認証フロー観点で見て"}]' "$OUT"; then
    pass ".vibehawk.yaml 読込 → language=ja + path_filters/instructions が JSON 化される"
  else
    fail ".vibehawk.yaml 読込シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
  fi

  rc=$(run_in "$WORK2" 20)
  if [[ "$rc" -eq 0 ]] && grep -qx "depth=focused" "$OUT"; then
    pass "FILES_COUNT=20 (10 ≤ < 50) → depth=focused"
  else
    fail "focused シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
  fi

  rc=$(run_in "$WORK2" 100)
  if [[ "$rc" -eq 0 ]] && grep -qx "depth=lightweight" "$OUT"; then
    pass "FILES_COUNT=100 (50 ≤ < 1000) → depth=lightweight"
  else
    fail "lightweight シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
  fi

  rc=$(run_in "$WORK2" 2000)
  if [[ "$rc" -eq 0 ]] && grep -qx "depth=summary_only" "$OUT"; then
    pass "FILES_COUNT=2000 (≥ 1000) → depth=summary_only"
  else
    fail "summary_only シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
  fi
else
  echo "  ! python3 + pyyaml が利用不可のため .vibehawk.yaml 読込シナリオをスキップ"
fi

rc=$(run_in "$WORK1" "")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "files_count=0" "$OUT" \
   && grep -qx "depth=full" "$OUT"; then
  pass "FILES_COUNT='' (空文字) → 0 として扱い depth=full"
else
  fail "FILES_COUNT='' シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

# 子 env からの明示除去で「環境変数の真の未設定」を検証する（空文字設定とは別ケース）。
rc=$(run_in "$WORK1" "__UNSET__")
if [[ "$rc" -eq 0 ]] \
   && grep -qx "files_count=0" "$OUT" \
   && grep -qx "depth=full" "$OUT"; then
  pass "FILES_COUNT 未設定 (env -u) → 0 として扱い depth=full"
else
  fail "FILES_COUNT 未設定 (env -u) シナリオの出力が想定と異なる: rc=$rc, output=$(cat "$OUT")"
fi

# GitHub Actions runner では GITHUB_OUTPUT が親シェル env から子へ継承されるため、
# 単に「assign しない」だけでは不十分。env -u GITHUB_OUTPUT で子 env から明示除去する（PR #185 と同じパターン）。
set +e
(cd "$WORK1" && env -u GITHUB_OUTPUT FILES_COUNT=5 bash "$SCRIPT") >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then
  pass "GITHUB_OUTPUT 未設定で非 0 終了する"
else
  fail "GITHUB_OUTPUT 未設定でも 0 終了してしまった"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
