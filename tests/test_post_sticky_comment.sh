#!/usr/bin/env bash
# Issue #219 — post-sticky-comment.sh の upsert ロジック検証
#
# gh コマンドを mock で差し替え、PATCH/POST/DELETE 呼び出し回数を観測する。
# 0 件 / 1 件 / 2+ 件 race condition / API error / github-actions[bot] 名義の 5+1 ケースで分岐挙動を検証する。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/post-sticky-comment.sh"

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

if [[ ! -x "$SCRIPT" ]]; then
  fail "${SCRIPT} が実行可能でない"
  exit 1
fi

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT" || true' EXIT

STICKY_BODY_INPUT='<!-- This is an auto-generated comment: sticky-summary by vibehawk -->
<!-- vibehawk:sticky -->
test body'

setup_gh_stub() {
  local list_response="$1"
  local stub_dir="${TMPDIR_ROOT}/bin"
  mkdir -p "$stub_dir"
  printf '%s\n' "$list_response" > "${TMPDIR_ROOT}/list-response.json"
  rm -f \
    "${TMPDIR_ROOT}/gh-calls.log" \
    "${TMPDIR_ROOT}/post-count.log" \
    "${TMPDIR_ROOT}/patch-count.log" \
    "${TMPDIR_ROOT}/delete-count.log"
  cat > "${stub_dir}/gh" <<EOF
#!/bin/bash
echo "\$@" >> "${TMPDIR_ROOT}/gh-calls.log"
case "\$*" in
  *--paginate*) cat "${TMPDIR_ROOT}/list-response.json"; exit 0 ;;
  *"-X POST"*) cat >/dev/null; echo POST >> "${TMPDIR_ROOT}/post-count.log"; printf '{"id":99,"html_url":"https://example.com/c/99"}\n'; exit 0 ;;
  *"-X PATCH"*) cat >/dev/null; echo PATCH >> "${TMPDIR_ROOT}/patch-count.log"; printf '{"id":99,"html_url":"https://example.com/c/99"}\n'; exit 0 ;;
  *"-X DELETE"*) echo DELETE >> "${TMPDIR_ROOT}/delete-count.log"; exit 0 ;;
esac
exit 0
EOF
  chmod +x "${stub_dir}/gh"
  export PATH="${stub_dir}:${PATH}"
}

count_lines() {
  local file="${TMPDIR_ROOT}/$1"
  if [[ -f "$file" ]]; then
    wc -l < "$file" | tr -d ' '
  else
    echo 0
  fi
}

run_script() {
  echo "$STICKY_BODY_INPUT" | REPO=hirokimry/vibehawk PR_NUMBER=1 OWNER=hirokimry bash "$SCRIPT" > /dev/null
}

echo "Case A: 0 件マッチ → POST 1 回"
setup_gh_stub '[]'
run_script
if [[ "$(count_lines post-count.log)" == "1" && "$(count_lines patch-count.log)" == "0" && "$(count_lines delete-count.log)" == "0" ]]; then
  pass "Case A (POST=1, PATCH=0, DELETE=0)"
else
  fail "Case A (POST=$(count_lines post-count.log), PATCH=$(count_lines patch-count.log), DELETE=$(count_lines delete-count.log))"
fi

echo "Case B: 1 件マッチ → PATCH 1 回"
setup_gh_stub '[{"id":111,"created_at":"2026-01-01T00:00:00Z","user":{"login":"vibehawk-for-hirokimry[bot]"},"body":"<!-- This is an auto-generated comment: sticky-summary by vibehawk -->\n<!-- vibehawk:sticky -->\nold"}]'
run_script
if [[ "$(count_lines post-count.log)" == "0" && "$(count_lines patch-count.log)" == "1" && "$(count_lines delete-count.log)" == "0" ]]; then
  pass "Case B (POST=0, PATCH=1, DELETE=0)"
else
  fail "Case B (POST=$(count_lines post-count.log), PATCH=$(count_lines patch-count.log), DELETE=$(count_lines delete-count.log))"
fi

echo "Case C: 2 件マッチ（race condition） → DELETE 1 + PATCH 1"
setup_gh_stub '[
  {"id":111,"created_at":"2026-01-01T00:00:00Z","user":{"login":"vibehawk-for-hirokimry[bot]"},"body":"<!-- This is an auto-generated comment: sticky-summary by vibehawk -->\n<!-- vibehawk:sticky -->\nold1"},
  {"id":222,"created_at":"2026-01-02T00:00:00Z","user":{"login":"vibehawk-for-hirokimry[bot]"},"body":"<!-- This is an auto-generated comment: sticky-summary by vibehawk -->\n<!-- vibehawk:sticky -->\nold2"}
]'
run_script
if [[ "$(count_lines post-count.log)" == "0" && "$(count_lines patch-count.log)" == "1" && "$(count_lines delete-count.log)" == "1" ]]; then
  pass "Case C (POST=0, PATCH=1, DELETE=1)"
else
  fail "Case C (POST=$(count_lines post-count.log), PATCH=$(count_lines patch-count.log), DELETE=$(count_lines delete-count.log))"
fi

echo "Case D: 3 件マッチ → DELETE 2 + PATCH 1"
setup_gh_stub '[
  {"id":111,"created_at":"2026-01-01T00:00:00Z","user":{"login":"vibehawk-for-hirokimry[bot]"},"body":"<!-- This is an auto-generated comment: sticky-summary by vibehawk -->\n<!-- vibehawk:sticky -->\nold1"},
  {"id":222,"created_at":"2026-01-02T00:00:00Z","user":{"login":"vibehawk-for-hirokimry[bot]"},"body":"<!-- This is an auto-generated comment: sticky-summary by vibehawk -->\n<!-- vibehawk:sticky -->\nold2"},
  {"id":333,"created_at":"2026-01-03T00:00:00Z","user":{"login":"vibehawk-for-hirokimry[bot]"},"body":"<!-- This is an auto-generated comment: sticky-summary by vibehawk -->\n<!-- vibehawk:sticky -->\nold3"}
]'
run_script
if [[ "$(count_lines post-count.log)" == "0" && "$(count_lines patch-count.log)" == "1" && "$(count_lines delete-count.log)" == "2" ]]; then
  pass "Case D (POST=0, PATCH=1, DELETE=2)"
else
  fail "Case D (POST=$(count_lines post-count.log), PATCH=$(count_lines patch-count.log), DELETE=$(count_lines delete-count.log))"
fi

echo "Case E: gh api list 失敗 → exit 0 + warning"
err_stub_dir="${TMPDIR_ROOT}/err-bin"
mkdir -p "$err_stub_dir"
cat > "${err_stub_dir}/gh" <<'EOF'
#!/bin/bash
echo "gh stub: forced failure" >&2
exit 1
EOF
chmod +x "${err_stub_dir}/gh"
err_out="${TMPDIR_ROOT}/case-e.out"
set +e
echo "$STICKY_BODY_INPUT" | PATH="${err_stub_dir}:${PATH}" REPO=hirokimry/vibehawk PR_NUMBER=1 OWNER=hirokimry bash "$SCRIPT" > "$err_out" 2>&1
exit_code=$?
set -e
if [[ "$exit_code" == "0" ]] && grep -q 'warning' "$err_out"; then
  pass "Case E (exit 0 + warning)"
else
  fail "Case E (exit_code=$exit_code, output=$(cat "$err_out"))"
fi

echo "Case F: github-actions[bot] 名義の skip-mark sticky も検出される (CPO 提案 2)"
setup_gh_stub '[{"id":444,"created_at":"2026-01-01T00:00:00Z","user":{"login":"github-actions[bot]"},"body":"<!-- This is an auto-generated comment: sticky-summary by vibehawk -->\n<!-- vibehawk:sticky -->\nskip-mark old"}]'
run_script
if [[ "$(count_lines post-count.log)" == "0" && "$(count_lines patch-count.log)" == "1" && "$(count_lines delete-count.log)" == "0" ]]; then
  pass "Case F (github-actions[bot] 名義検出: POST=0, PATCH=1, DELETE=0)"
else
  fail "Case F (POST=$(count_lines post-count.log), PATCH=$(count_lines patch-count.log), DELETE=$(count_lines delete-count.log))"
fi

echo "==="
echo "passed: $PASSED, failed: $FAILED"
exit "$FAILED"
