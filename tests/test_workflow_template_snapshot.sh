#!/usr/bin/env bash
# vibehawk workflow テンプレートのスナップショット検証（Issue #29）
#
# 目的: `templates/.github/workflows/vibehawk-review.yml` および
#      `.github/workflows/vibehawk-review.yml`（dogfooding 用）が
#      `.claude/rules/autonomous-restrictions.md` §6 で禁止された
#      権限・トリガー・条件削除を含まないことを CI で機械検証する。
#
# CISO Major 条件: 自動化があってこそ permissions 固定の実効性が高い。
# CI 必須実行（required check）として位置づける。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

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

# 検証対象ファイル
TARGETS=(
  "templates/.github/workflows/vibehawk-review.yml"
  ".github/workflows/vibehawk-review.yml"
)

echo "=== vibehawk workflow テンプレート スナップショット検証 ==="

# 各対象ファイルが存在し、forbidden パターンを含まないこと
for target in "${TARGETS[@]}"; do
  if [[ ! -f "$target" ]]; then
    fail "$target が存在しない（テンプレートとして必須）"
    continue
  fi
  pass "$target が存在する"

  # コメント行を除外（YAML として無効な状態でないことの軽い保護）
  body="$(awk '!/^[[:space:]]*#/' "$target")"

  # 禁止権限パターン（autonomous-restrictions.md §6）
  declare -a forbidden_perms=(
    "administration:[[:space:]]*write"
    "secrets:[[:space:]]*write"
    "workflows:[[:space:]]*write"
    "id-token:[[:space:]]*write"
  )
  declare -a forbidden_perm_labels=(
    "administration: write"
    "secrets: write"
    "workflows: write"
    "id-token: write"
  )

  for i in "${!forbidden_perms[@]}"; do
    pattern="${forbidden_perms[$i]}"
    label="${forbidden_perm_labels[$i]}"
    if echo "$body" | grep -E "$pattern" > /dev/null; then
      fail "$target に禁止権限 '$label' が混入"
    else
      pass "$target に禁止権限 '$label' が含まれない"
    fi
  done

  # 禁止トリガー: pull_request_target（Fork PR + secrets 参照は最大の攻撃経路）
  if echo "$body" | grep -E "^[[:space:]]*pull_request_target:" > /dev/null; then
    fail "$target に禁止トリガー 'pull_request_target' が混入"
  else
    pass "$target に禁止トリガー 'pull_request_target' が含まれない"
  fi

  # 禁止 secrets: VIBEHAWK_APP_ID / VIBEHAWK_PRIVATE_KEY（Issue #22 で削除済み）
  declare -a forbidden_secrets=(
    "VIBEHAWK_APP_ID"
    "VIBEHAWK_PRIVATE_KEY"
  )
  for sec in "${forbidden_secrets[@]}"; do
    if echo "$body" | grep -F "$sec" > /dev/null; then
      fail "$target に禁止 secret '$sec' が混入（Issue #22 で削除済みのはず）"
    else
      pass "$target に禁止 secret '$sec' が含まれない"
    fi
  done

  # 禁止 Action: actions/create-github-app-token（Issue #22 で削除済み）
  if echo "$body" | grep -F "actions/create-github-app-token" > /dev/null; then
    fail "$target に actions/create-github-app-token が混入（Issue #22 で削除済みのはず）"
  else
    pass "$target に actions/create-github-app-token が含まれない"
  fi
done

# templates/ と .github/ のテンプレートが完全一致していることを検証（snapshot 等価性）
# dogfooding 用 workflow は配布用テンプレートと同一でなければならない（ドリフト防止）
if [[ -f "${TARGETS[0]}" && -f "${TARGETS[1]}" ]]; then
  if diff -u "${TARGETS[0]}" "${TARGETS[1]}" > /dev/null; then
    pass "templates/.github/workflows/vibehawk-review.yml と .github/workflows/vibehawk-review.yml が完全一致"
  else
    fail "templates/.github/workflows/vibehawk-review.yml と .github/workflows/vibehawk-review.yml が乖離している（ドリフト検出）"
    echo "    差分:"
    diff -u "${TARGETS[0]}" "${TARGETS[1]}" | head -20 | sed 's/^/      /'
  fi
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
