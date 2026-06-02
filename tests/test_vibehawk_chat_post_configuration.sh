#!/usr/bin/env bash
# scripts/ci/vibehawk-chat/post-configuration.sh の単体テスト（Issue #294、epic #289 子5）。
#   - .vibehawk.yaml ありで値表示 / 不在で default / 不正 YAML で default フォールバック
#   - 外部 URL を含まない / env 欠落で非 0
# post-configuration.sh はカレントの .vibehawk.yaml を読むため、一時作業ディレクトリで cd して検証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-chat/post-configuration.sh"

PASSED=0
FAILED=0
pass() { echo "  ✓ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ✗ $1"; FAILED=$((FAILED + 1)); }

echo "=== scripts/ci/vibehawk-chat/post-configuration.sh 単体テスト ==="
if [[ -f "$SCRIPT" ]]; then pass "post-configuration.sh が存在する"; else fail "post-configuration.sh が存在しない"; exit 1; fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT
STUB_DIR="${TMP_DIR}/stub"; mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "issue" && "${2:-}" == "comment" ]]; then
  shift 2
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--body" ]]; then printf '%s' "$2" > "$BODY_LOG"; exit 0; fi
    shift
  done
fi
exit 0
STUB
chmod +x "$STUB_DIR/gh"

BODY="${TMP_DIR}/body.log"

# 一時作業ディレクトリで実行（カレントの .vibehawk.yaml を読むため）
run_in_workdir() {
  local workdir="$1"
  : > "$BODY"
  local rc=0
  ( cd "$workdir" && PATH="$STUB_DIR:$PATH" BODY_LOG="$BODY" GH_TOKEN=t ISSUE_NUMBER=42 bash "$SCRIPT" >/dev/null 2>&1 ) || rc=$?
  echo "$rc"
}

echo "=== Case 1: .vibehawk.yaml ありで設定値を表示 ==="
WD1="${TMP_DIR}/wd1"; mkdir -p "$WD1"
cat > "$WD1/.vibehawk.yaml" <<'EOF'
language: ja
size_limits:
  full_review_files: 50
  focused_review_files: 100
  skip_inline_files: 2000
path_filters:
  - "!**/*.lock"
EOF
rc=$(run_in_workdir "$WD1")
if [[ "$rc" -eq 0 ]] && grep -qF "language: ja" "$BODY" && grep -qF "full_review_files: 50" "$BODY" \
   && grep -qF ".vibehawk.yaml" "$BODY" && grep -qF "path_filters: 1 件" "$BODY"; then
  pass ".vibehawk.yaml ありで設定値（language/size_limits/path_filters 件数）を表示"
else
  fail "Case1 不一致: rc=$rc body=$(head -c 400 "$BODY")"
fi

echo "=== Case 2: .vibehawk.yaml 不在で default を表示 ==="
WD2="${TMP_DIR}/wd2"; mkdir -p "$WD2"
rc=$(run_in_workdir "$WD2")
if [[ "$rc" -eq 0 ]] && grep -qF "language: en" "$BODY" && grep -qF "full_review_files: 30" "$BODY" \
   && grep -qF "default" "$BODY"; then
  pass ".vibehawk.yaml 不在で default 値を表示"
else
  fail "Case2 不一致: rc=$rc body=$(head -c 400 "$BODY")"
fi

echo "=== Case 3: 不正 YAML で default フォールバック ==="
WD3="${TMP_DIR}/wd3"; mkdir -p "$WD3"
printf '%s\n' "language: : : invalid: [unclosed" > "$WD3/.vibehawk.yaml"
rc=$(run_in_workdir "$WD3")
if [[ "$rc" -eq 0 ]] && grep -qF "language: en" "$BODY" && grep -qF "default" "$BODY"; then
  pass "不正 YAML で default にフォールバック（クラッシュしない）"
else
  fail "Case3 不一致: rc=$rc body=$(head -c 400 "$BODY")"
fi

echo "=== Case 4: 外部 URL を含まない ==="
if ! grep -qE 'https?://' "$BODY"; then
  pass "configuration 本文に外部 URL を含まない"
else
  fail "configuration 本文に外部 URL が含まれる"
fi

echo "=== Case 5: 必須 env 未設定（ISSUE_NUMBER 欠落）→ 非 0 終了 ==="
set +e
( cd "$WD2" && PATH="$STUB_DIR:$PATH" BODY_LOG="$BODY" GH_TOKEN=t bash "$SCRIPT" >/dev/null 2>&1 )
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then pass "ISSUE_NUMBER 未設定で非 0 終了"; else fail "ISSUE_NUMBER 未設定でも 0 終了"; fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
