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

# YAML としてパース可能か検証する（Issue #333: description 値内の「例: 」のコロンで
# YAML マッピング誤認が起き、grep ベースの検証をすり抜けて main の release.yml が壊れた再発防止）。
# pyyaml は macos/windows runner には同梱されないため、不在時はスキップする（CI ubuntu / ローカルで検証）。
if command -v python3 > /dev/null 2>&1 && python3 -c "import yaml" 2> /dev/null; then
  for wf in "$WORKFLOW" "${REPO_ROOT}/.github/workflows/release-tag.yml"; do
    if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$wf" 2> /dev/null; then
      pass "YAML としてパース可能: $(basename "$wf")"
    else
      fail "YAML パースに失敗: $(basename "$wf")（workflow file issue で実行不能になる）"
    fi
  done
else
  echo "  ⚠ pyyaml が見つからない → YAML パース検証をスキップ（CI ubuntu では利用可）"
fi

body="$(awk '!/^[[:space:]]*#/' "$WORKFLOW")"

# release トリガー（誤 publish 防止）
if echo "$body" | grep -E "^[[:space:]]*release:" > /dev/null; then
  pass "release トリガーが設定されている"
else
  fail "release トリガーが設定されていない"
fi

# workflow_dispatch トリガー（GITHUB_TOKEN 製 Release からの publish 起動経路、Issue #333）
if echo "$body" | grep -E "^[[:space:]]*workflow_dispatch:" > /dev/null; then
  pass "workflow_dispatch トリガーが設定されている（Issue #333）"
else
  fail "workflow_dispatch トリガーが設定されていない（自動 Release から publish を起動できない）"
fi

# workflow_dispatch の tag 入力（checkout ref / concurrency で参照）
if echo "$body" | grep -E "^[[:space:]]*tag:" > /dev/null; then
  pass "workflow_dispatch の tag 入力が定義されている"
else
  fail "workflow_dispatch の tag 入力が定義されていない"
fi

# checkout ref / concurrency が両トリガー対応（inputs.tag フォールバック）
if echo "$body" | grep -F "inputs.tag" > /dev/null; then
  pass "ref / concurrency が inputs.tag フォールバックを持つ（両トリガー対応）"
else
  fail "inputs.tag フォールバックがない（workflow_dispatch 経路で tag が解決されない）"
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

# OIDC 一本化: NODE_AUTH_TOKEN / NPM_TOKEN を参照しない（Issue #321）
if echo "$body" | grep -E "NODE_AUTH_TOKEN|NPM_TOKEN" > /dev/null; then
  fail "NODE_AUTH_TOKEN / NPM_TOKEN が参照されている（OIDC 一本化されていない）"
else
  pass "NODE_AUTH_TOKEN / NPM_TOKEN を参照しない（OIDC trusted publishing 一本化、Issue #321）"
fi

# OIDC trusted publishing の Node 要件（Node >= 22.14.0、Issue #321）
if echo "$body" | grep -E "node-version:[[:space:]]*'2[2-9]" > /dev/null; then
  pass "node-version が 22 以上（OIDC trusted publishing 要件 Node >= 22.14.0）"
else
  fail "node-version が 22 未満（OIDC trusted publishing 要件 Node >= 22.14.0 を満たさない）"
fi

# npm >= 11.5.1 を保証する明示更新ステップ（Issue #321）
if echo "$body" | grep -E "npm install -g npm@" > /dev/null; then
  pass "npm を明示更新するステップがある（npm >= 11.5.1 保証、Issue #321）"
else
  fail "npm を明示更新するステップがない（npm >= 11.5.1 が保証されない）"
fi

# release-tag.yml 側: gh workflow run のため actions: write を持つ（Issue #333）
TAG_WORKFLOW="${REPO_ROOT}/.github/workflows/release-tag.yml"
if [[ -f "$TAG_WORKFLOW" ]]; then
  pass "release-tag.yml が存在する"
  tag_body="$(awk '!/^[[:space:]]*#/' "$TAG_WORKFLOW")"
  if echo "$tag_body" | grep -E "actions:[[:space:]]*write" > /dev/null; then
    pass "release-tag.yml に actions: write がある（gh workflow run 用、Issue #333）"
  else
    fail "release-tag.yml に actions: write がない（release.yml を起動できない）"
  fi
  if echo "$tag_body" | grep -F "release-tag-on-main.sh" > /dev/null; then
    pass "release-tag.yml が release-tag-on-main.sh を呼ぶ"
  else
    fail "release-tag.yml が release-tag-on-main.sh を呼ばない"
  fi
else
  fail "release-tag.yml が存在しない"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
