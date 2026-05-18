#!/usr/bin/env bash
# vibehawk release workflow の最小要件検証（Issue #30）
#
# CISO Critical 条件:
# - GitHub Actions OIDC 経由の publish のみ
# - npm provenance 署名（npm publish --provenance）
# - publish アカウントの 2FA は npmjs.com 側で設定（test 範囲外）

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

WORKFLOW="${REPO_ROOT}/.github/workflows/release.yml"

echo "=== vibehawk release workflow 検証 ==="

if [[ -f "$WORKFLOW" ]]; then
  pass "release.yml が存在する"
else
  fail "release.yml が存在しない"
  echo "=== 結果: $PASSED passed, $FAILED failed ==="
  exit 1
fi

body="$(awk '!/^[[:space:]]*#/' "$WORKFLOW")"

# release トリガー（誤 publish 防止）
if echo "$body" | grep -E "^[[:space:]]*release:" > /dev/null; then
  pass "release トリガーが設定されている"
else
  fail "release トリガーが設定されていない"
fi

# push / pull_request トリガー不在（誤 publish 防止）
for forbidden_trigger in "^[[:space:]]*push:" "^[[:space:]]*pull_request:" "^[[:space:]]*pull_request_target:"; do
  if echo "$body" | grep -E "$forbidden_trigger" > /dev/null; then
    fail "禁止トリガー '$forbidden_trigger' が含まれる"
  else
    pass "禁止トリガー '$forbidden_trigger' が含まれない"
  fi
done

# id-token: write（OIDC publish に必須）
if echo "$body" | grep -E "id-token:[[:space:]]*write" > /dev/null; then
  pass "permissions: id-token: write が設定されている（OIDC publish 必須）"
else
  fail "permissions: id-token: write が設定されていない（OIDC publish 不可）"
fi

# 禁止権限不在
declare -a forbidden_perms=(
  "administration:[[:space:]]*write"
  "secrets:[[:space:]]*write"
  "workflows:[[:space:]]*write"
)
for pattern in "${forbidden_perms[@]}"; do
  if echo "$body" | grep -E "$pattern" > /dev/null; then
    fail "禁止権限 '$pattern' が含まれる"
  else
    pass "禁止権限 '$pattern' が含まれない"
  fi
done

# npm publish --provenance
if echo "$body" | grep -F "npm publish --provenance" > /dev/null; then
  pass "npm publish --provenance が設定されている（CISO Critical 条件）"
else
  fail "npm publish --provenance が設定されていない（provenance 署名なしで publish される）"
fi

# --access public（OSS 配布のため明示）
if echo "$body" | grep -- "--access public" > /dev/null; then
  pass "--access public が設定されている"
else
  fail "--access public が設定されていない"
fi

# tag と version の整合確認ステップ
# Issue #179 で実体は scripts/ci/release/verify-tag-version.sh に切り出された。
# workflow からはラッパー呼び出しのみ。スクリプト本体の存在も併せて検証する。
if echo "$body" | grep -F "scripts/ci/release/verify-tag-version.sh" > /dev/null; then
  pass "tag と package.json version の整合確認ステップが存在する（scripts/ci/release/verify-tag-version.sh）"
else
  fail "tag と package.json version の整合確認ステップが存在しない（scripts/ci/release/verify-tag-version.sh 参照なし）"
fi
if [[ -f "${REPO_ROOT}/scripts/ci/release/verify-tag-version.sh" ]]; then
  pass "scripts/ci/release/verify-tag-version.sh が実在する"
else
  fail "scripts/ci/release/verify-tag-version.sh が実在しない"
fi
# テスト実行ステップ（切り出し済み）
if echo "$body" | grep -F "scripts/ci/release/run-tests.sh" > /dev/null; then
  pass "テスト実行ステップが scripts/ci/release/run-tests.sh を参照する"
else
  fail "テスト実行ステップが scripts/ci/release/run-tests.sh を参照しない"
fi
if [[ -f "${REPO_ROOT}/scripts/ci/release/run-tests.sh" ]]; then
  pass "scripts/ci/release/run-tests.sh が実在する"
else
  fail "scripts/ci/release/run-tests.sh が実在しない"
fi

# package.json の publishConfig.provenance: true
if node -e '
const p = require("./package.json");
if (!p.publishConfig) process.exit(1);
if (p.publishConfig.provenance !== true) process.exit(1);
if (p.publishConfig.access !== "public") process.exit(1);
'; then
  pass "package.json の publishConfig.provenance: true / access: public が設定されている"
else
  fail "package.json の publishConfig 設定が不足"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
