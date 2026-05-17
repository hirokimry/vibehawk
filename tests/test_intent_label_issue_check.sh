#!/usr/bin/env bash
# scripts/ci/intent-checks/intent-label-issue-check.sh の単体テスト。
#
# 実際の GitHub API 呼び出しは行わない（CI で gh 認証情報を必須にしないため）。
# PATH に gh スタブを差し込み、Issue ラベル数の分岐を検証する。

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

SCRIPT="${REPO_ROOT}/scripts/ci/intent-checks/intent-label-issue-check.sh"

echo "=== scripts/ci/intent-checks/intent-label-issue-check.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "スクリプトが存在する"
else
  fail "スクリプトが存在しない"
  exit 1
fi

# 必須環境変数の検証
set +e
err_out="$(REPO=test/repo bash "$SCRIPT" 2>&1)"
err_code=$?
set -e
if [[ $err_code -ne 0 ]] && echo "$err_out" | grep -qF "ISSUE_NUMBER"; then
  pass "ISSUE_NUMBER 未指定で非 0 終了"
else
  fail "ISSUE_NUMBER バリデーション挙動が想定と異なる: exit=$err_code, out='$err_out'"
fi

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT

# シナリオ 1: 許可 intent 1 つだけ → exit 0
cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "api" ]]; then
  # 許可 intent 1 つ
  echo '[{"name":"intent/feature"},{"name":"area/ci"}]'
  exit 0
fi
if [[ "\$1" == "issue" && "\$2" == "comment" ]]; then
  echo "GH_ISSUE_COMMENT_CALLED: \$*" >> "$STUB_DIR/calls.log"
  exit 0
fi
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out="$(PATH="$STUB_DIR:$PATH" ISSUE_NUMBER=999 REPO=test/repo bash "$SCRIPT" 2>&1)"
code=$?
set -e
if [[ $code -eq 0 ]]; then
  pass "許可 intent 1 つで exit 0"
else
  fail "許可 intent 1 つ分岐の挙動が想定と異なる: exit=$code, out='$out'"
fi

if [[ ! -f "$STUB_DIR/calls.log" ]]; then
  pass "許可 intent 1 つでコメント投稿されない"
else
  fail "許可 intent 1 つでコメントが投稿された: $(cat "$STUB_DIR/calls.log")"
fi

# シナリオ 2: intent ラベル不在 → exit 1 + コメント投稿
rm -f "$STUB_DIR/calls.log"
cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "api" ]]; then
  echo '[{"name":"area/ci"}]'
  exit 0
fi
if [[ "\$1" == "issue" && "\$2" == "comment" ]]; then
  echo "GH_ISSUE_COMMENT_CALLED: \$*" >> "$STUB_DIR/calls.log"
  exit 0
fi
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out2="$(PATH="$STUB_DIR:$PATH" ISSUE_NUMBER=999 REPO=test/repo bash "$SCRIPT" 2>&1)"
code2=$?
set -e
if [[ $code2 -eq 1 ]]; then
  pass "intent ラベル不在で exit 1"
else
  fail "intent ラベル不在の exit code が 1 ではない: exit=$code2, out='$out2'"
fi

if [[ -f "$STUB_DIR/calls.log" ]] && grep -qF "GH_ISSUE_COMMENT_CALLED" "$STUB_DIR/calls.log"; then
  pass "intent ラベル不在で gh issue comment が呼ばれる"
else
  fail "intent ラベル不在で gh issue comment が呼ばれていない"
fi

# シナリオ 3: 許可 intent 2 つ → exit 1 + コメント投稿
rm -f "$STUB_DIR/calls.log"
cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "api" ]]; then
  echo '[{"name":"intent/feature"},{"name":"intent/bugfix"}]'
  exit 0
fi
if [[ "\$1" == "issue" && "\$2" == "comment" ]]; then
  echo "GH_ISSUE_COMMENT_CALLED: \$*" >> "$STUB_DIR/calls.log"
  exit 0
fi
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out3="$(PATH="$STUB_DIR:$PATH" ISSUE_NUMBER=999 REPO=test/repo bash "$SCRIPT" 2>&1)"
code3=$?
set -e
if [[ $code3 -eq 1 ]]; then
  pass "許可 intent 2 つで exit 1"
else
  fail "許可 intent 2 つの exit code が 1 ではない: exit=$code3, out='$out3'"
fi

# シナリオ 4: 未知 intent（intent/unknown）混在 → exit 1
rm -f "$STUB_DIR/calls.log"
cat > "$STUB_DIR/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "api" ]]; then
  echo '[{"name":"intent/feature"},{"name":"intent/unknown"}]'
  exit 0
fi
if [[ "\$1" == "issue" && "\$2" == "comment" ]]; then
  echo "GH_ISSUE_COMMENT_CALLED: \$*" >> "$STUB_DIR/calls.log"
  exit 0
fi
exit 0
EOF
chmod +x "$STUB_DIR/gh"

set +e
out4="$(PATH="$STUB_DIR:$PATH" ISSUE_NUMBER=999 REPO=test/repo bash "$SCRIPT" 2>&1)"
code4=$?
set -e
if [[ $code4 -eq 1 ]]; then
  pass "未知 intent（intent/unknown）混在で exit 1"
else
  fail "未知 intent 混在の exit code が 1 ではない: exit=$code4, out='$out4'"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
