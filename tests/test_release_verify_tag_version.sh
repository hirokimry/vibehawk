#!/usr/bin/env bash
# tests/test_release_verify_tag_version.sh
#
# scripts/ci/release/verify-tag-version.sh の単体テスト（Issue #179）。
#
# 検証内容:
#   1. GITHUB_REF_NAME 未設定で exit 非 0（必須環境変数）
#   2. tag と package.json version が一致して exit 0
#   3. 不一致で exit 1
#   4. `v` プレフィックスの除去（v1.2.3 → 1.2.3）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/release/verify-tag-version.sh"

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

echo "=== scripts/ci/release/verify-tag-version.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "verify-tag-version.sh が存在する"
else
  fail "verify-tag-version.sh が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# shebang / set -euo pipefail
first_line="$(head -n 1 "$SCRIPT")"
if [[ "$first_line" == "#!/usr/bin/env bash" ]]; then
  pass "shebang が #!/usr/bin/env bash"
else
  fail "shebang が想定外: $first_line"
fi

if grep -qE "^set -euo pipefail$" "$SCRIPT"; then
  pass "set -euo pipefail を備える"
else
  fail "set -euo pipefail がない"
fi

# node コマンドが必要
if ! command -v node > /dev/null 2>&1; then
  fail "node コマンドが PATH にない（package.json バージョン読み取り不可）"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# サンドボックス: package.json を持つ一時ディレクトリ
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mkdir -p "${TMPDIR_TEST}/repo"
cat > "${TMPDIR_TEST}/repo/package.json" <<'EOF'
{
  "name": "test-fixture",
  "version": "1.2.3"
}
EOF

set +e
( cd "${TMPDIR_TEST}/repo" && env -u GITHUB_REF_NAME bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -ne 0 ]]; then
  pass "GITHUB_REF_NAME 未設定 → exit 非 0 ($exit_code)"
else
  fail "GITHUB_REF_NAME 未設定でも成功してしまう"
fi

set +e
( cd "${TMPDIR_TEST}/repo" && GITHUB_REF_NAME="v1.2.3" bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -eq 0 ]]; then
  pass "tag v1.2.3 と version 1.2.3 が一致 → exit 0"
else
  fail "一致しているのに exit $exit_code"
fi

set +e
( cd "${TMPDIR_TEST}/repo" && GITHUB_REF_NAME="1.2.3" bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -eq 0 ]]; then
  pass "tag 1.2.3 (v なし) と version 1.2.3 が一致 → exit 0"
else
  fail "v なし tag 一致でも exit $exit_code"
fi

set +e
output=$(cd "${TMPDIR_TEST}/repo" && GITHUB_REF_NAME="v9.9.9" bash "$SCRIPT" 2>&1)
exit_code=$?
set -e
if [[ "$exit_code" -eq 1 ]]; then
  pass "tag v9.9.9 と version 1.2.3 が不一致 → exit 1"
else
  fail "不一致なのに exit $exit_code"
fi
if grep -qF "::error::tag (9.9.9) と package.json version (1.2.3) が不一致" <<< "$output"; then
  pass "::error::形式のメッセージが出力される"
else
  fail "::error::メッセージが想定と異なる: $output"
fi

# RELEASE_TAG（明示渡し）を最優先する（workflow_dispatch 対策、Issue #333）
set +e
( cd "${TMPDIR_TEST}/repo" && RELEASE_TAG="v1.2.3" bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -eq 0 ]]; then
  pass "RELEASE_TAG=v1.2.3 と version 1.2.3 が一致 → exit 0"
else
  fail "RELEASE_TAG 一致でも exit $exit_code"
fi

# workflow_dispatch 再現: GITHUB_REF_NAME=main でも RELEASE_TAG が優先される（Issue #333）
set +e
( cd "${TMPDIR_TEST}/repo" && GITHUB_REF_NAME="main" RELEASE_TAG="v1.2.3" bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -eq 0 ]]; then
  pass "GITHUB_REF_NAME=main でも RELEASE_TAG=v1.2.3 が優先され exit 0"
else
  fail "RELEASE_TAG 優先が効かず exit $exit_code（GITHUB_REF_NAME=main を tag と誤認）"
fi

# RELEASE_TAG / GITHUB_REF_NAME ともに未設定 → exit 非 0
set +e
( cd "${TMPDIR_TEST}/repo" && env -u GITHUB_REF_NAME -u RELEASE_TAG bash "$SCRIPT" > /dev/null 2>&1 )
exit_code=$?
set -e
if [[ "$exit_code" -ne 0 ]]; then
  pass "RELEASE_TAG / GITHUB_REF_NAME ともに未設定 → exit 非 0 ($exit_code)"
else
  fail "両方未設定でも成功してしまう"
fi

set +e
output=$(cd "${TMPDIR_TEST}/repo" && GITHUB_REF_NAME="v1.2.3" bash "$SCRIPT" 2>&1)
exit_code=$?
set -e
if [[ "$exit_code" -eq 0 ]]; then
  pass "成功時に exit 0 で終了する"
else
  fail "成功時の exit_code が想定外: exit=$exit_code, output='$output'"
fi
if grep -qF 'tag と version の整合確認 OK: 1.2.3' <<< "$output"; then
  pass "成功時メッセージ 'tag と version の整合確認 OK: 1.2.3' が出力される"
else
  fail "成功時メッセージが想定と異なる: $output"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
