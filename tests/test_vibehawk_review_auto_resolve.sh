#!/usr/bin/env bash
# scripts/ci/vibehawk-review/auto-resolve.sh の単体テスト（Issue #167）。
#
# 設計:
#   gh コマンドをスタブし、引数パターンで分岐させて mutation 呼び出し回数 + 取得
#   thread 情報を制御する。スタブ実行時に mutation の呼び出しを log file に記録し、
#   テストで件数・対象 id を assert する。
#
# シナリオ:
#   1. resolved_thread_ids が空配列 → mutation 0 回（skip ログ）
#   2. resolved_thread_ids 1 件 + author.login が vibehawk-for-<owner> → mutation 1 回
#   3. resolved_thread_ids 1 件 + author.login が別 bot（coderabbitai） → mutation 0 回
#   4. resolved_thread_ids 1 件 + 該当 thread が GraphQL 応答に無い → mutation 0 回
#   5. resolved_thread_ids 複数件、混在 → 該当 mutation のみ実行
#   6. 必須 env 欠落 → 非 0 終了
#   7. resolved_thread_ids に node_id 形式不一致（コマンド注入文字列等） → mutation 0 回
#   8. 個別 mutation 失敗 → warning + skip、step 全体は 0 終了

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

SCRIPT="${REPO_ROOT}/scripts/ci/vibehawk-review/auto-resolve.sh"

echo "=== scripts/ci/vibehawk-review/auto-resolve.sh 単体テスト ==="

if [[ -f "$SCRIPT" ]]; then
  pass "auto-resolve.sh が存在する"
else
  fail "auto-resolve.sh が存在しない"
  # 前提ファイル不在 → 後続テストは全て無意味なので即終了
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STUB_DIR="${TMP_DIR}/stub"
mkdir -p "$STUB_DIR"

# gh スタブを生成する。
#
# 動作:
#   - `gh api graphql -f query='query(...)' ...` (reviewThreads クエリ): 第 1 引数の
#     THREADS_JSON_FILE の内容をそのまま stdout に出力（テスト側で事前準備）。
#   - `gh api graphql -f query='mutation(...)' ...`: mutation 呼び出しを MUTATION_LOG に
#     1 行追記（"mutation:<threadId>" 形式）し、`{"data":{"resolveReviewThread":...}}` を返す。
#     MUTATION_FAIL_IDS に列挙された thread id は失敗（非 0 終了）させる。
#
# 引数:
#   $1: テストシナリオ用の reviewThreads.json 内容
#   $2: 失敗させたい thread id（カンマ区切り）、空文字列なら全成功
make_gh_stub() {
  local threads_json="$1"
  local fail_ids="$2"
  local threads_file="$STUB_DIR/threads.json"
  printf '%s' "$threads_json" > "$threads_file"
  printf '%s' "$fail_ids" > "$STUB_DIR/fail_ids.txt"
  : > "$STUB_DIR/mutation_log.txt"
  cat > "$STUB_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
# テスト用 gh スタブ: api graphql の query/mutation を引数判定して分岐する。
STUB_DIR_SELF="$(cd "$(dirname "$0")" && pwd)"
MUTATION_LOG="${STUB_DIR_SELF}/mutation_log.txt"
THREADS_FILE="${STUB_DIR_SELF}/threads.json"
FAIL_IDS_FILE="${STUB_DIR_SELF}/fail_ids.txt"

# 第 1 / 第 2 引数で api graphql 判定
if [[ "${1:-}" != "api" || "${2:-}" != "graphql" ]]; then
  echo "STUB ERROR: 想定外の gh 呼び出し: $*" >&2
  exit 1
fi

# 残り引数から query 内容と -F id=... を取り出す
query_str=""
id_value=""
i=3
args=("$@")
while [[ $i -le $# ]]; do
  arg="${args[$((i - 1))]}"
  if [[ "$arg" == "-f" && $i -lt $# ]]; then
    next="${args[$i]}"
    if [[ "$next" == query=* ]]; then
      query_str="${next#query=}"
    fi
    i=$((i + 2))
    continue
  fi
  if [[ "$arg" == "-F" && $i -lt $# ]]; then
    next="${args[$i]}"
    if [[ "$next" == id=* ]]; then
      id_value="${next#id=}"
    fi
    i=$((i + 2))
    continue
  fi
  i=$((i + 1))
done

if [[ "$query_str" == *"resolveReviewThread"* ]]; then
  # mutation 呼び出し記録
  echo "mutation:${id_value}" >> "$MUTATION_LOG"
  # 指定された id は失敗扱い
  fail_ids="$(cat "$FAIL_IDS_FILE" 2>/dev/null || echo "")"
  IFS=',' read -ra fail_arr <<< "$fail_ids"
  for fid in "${fail_arr[@]}"; do
    if [[ -n "$fid" && "$fid" == "$id_value" ]]; then
      echo "STUB: mutation $id_value を失敗扱い" >&2
      exit 1
    fi
  done
  printf '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}\n'
  exit 0
fi

if [[ "$query_str" == *"reviewThreads"* ]]; then
  cat "$THREADS_FILE"
  exit 0
fi

echo "STUB ERROR: 未対応 query: $query_str" >&2
exit 1
STUB_EOF
  chmod +x "$STUB_DIR/gh"
}

# テスト実行ヘルパー
run_script() {
  # Usage: run_script <structured_output_json> <reviewThreads_json> [<mutation_fail_ids>]
  local payload="$1"
  local threads_json="$2"
  local fail_ids="${3:-}"
  make_gh_stub "$threads_json" "$fail_ids"
  local stdout_file="${TMP_DIR}/stdout"
  local runner_temp="${TMP_DIR}/runner_temp"
  mkdir -p "$runner_temp"
  local rc=0
  PATH="$STUB_DIR:$PATH" \
    GH_TOKEN="dummy-token" \
    REPO="hirokimry/vibehawk" \
    PR_NUMBER=42 \
    OWNER="hirokimry" \
    STRUCTURED_OUTPUT="$payload" \
    RUNNER_TEMP="$runner_temp" \
    bash "$SCRIPT" > "$stdout_file" 2>&1 || rc=$?
  echo "$rc"
}

mutation_count() {
  if [[ -f "$STUB_DIR/mutation_log.txt" ]]; then
    wc -l < "$STUB_DIR/mutation_log.txt" | tr -d ' '
  else
    echo 0
  fi
}

# ヘルパー: reviewThreads JSON テンプレート
threads_json_with() {
  # Usage: threads_json_with <id1> <login1> [<id2> <login2> ...]
  local nodes=""
  while [[ $# -gt 0 ]]; do
    local tid="$1"
    local login="$2"
    shift 2
    if [[ -n "$nodes" ]]; then
      nodes="${nodes},"
    fi
    nodes="${nodes}$(printf '{"id":"%s","comments":{"nodes":[{"author":{"login":"%s"}}]}}' "$tid" "$login")"
  done
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[%s]}}}}}' "$nodes"
}

# ============================================================
# シナリオ 1: resolved_thread_ids が空配列 → mutation 0 回
# ============================================================
EMPTY_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha","comments":[],"resolved_thread_ids":[]}'
THREADS_EMPTY="$(threads_json_with)"
rc=$(run_script "$EMPTY_PAYLOAD" "$THREADS_EMPTY")
if [[ "$rc" -eq 0 ]] && [[ "$(mutation_count)" -eq 0 ]] \
   && grep -F "解決対象スレッドなし" "${TMP_DIR}/stdout" > /dev/null; then
  pass "シナリオ 1: resolved_thread_ids が空配列 → mutation 0 回 + skip ログ"
else
  fail "シナリオ 1 失敗: rc=$rc, mutation=$(mutation_count)"
  cat "${TMP_DIR}/stdout"
fi

# ============================================================
# シナリオ 1-bis: resolved_thread_ids 未定義 → mutation 0 回（フィールド省略でも吸収）
# ============================================================
NO_FIELD_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha","comments":[]}'
rc=$(run_script "$NO_FIELD_PAYLOAD" "$THREADS_EMPTY")
if [[ "$rc" -eq 0 ]] && [[ "$(mutation_count)" -eq 0 ]]; then
  pass "シナリオ 1-bis: resolved_thread_ids 未定義 → mutation 0 回（過渡期互換）"
else
  fail "シナリオ 1-bis 失敗: rc=$rc, mutation=$(mutation_count)"
fi

# ============================================================
# シナリオ 2: 1 件 + author.login が vibehawk-for-hirokimry → mutation 1 回
# ============================================================
ONE_OWN_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha","comments":[],"resolved_thread_ids":["PRRT_kwDOAAA"]}'
THREADS_OWN="$(threads_json_with "PRRT_kwDOAAA" "vibehawk-for-hirokimry")"
rc=$(run_script "$ONE_OWN_PAYLOAD" "$THREADS_OWN")
if [[ "$rc" -eq 0 ]] && [[ "$(mutation_count)" -eq 1 ]] \
   && grep -F "mutation:PRRT_kwDOAAA" "$STUB_DIR/mutation_log.txt" > /dev/null \
   && grep -F "resolved=1" "${TMP_DIR}/stdout" > /dev/null; then
  pass "シナリオ 2: 自身 bot 1 件 → mutation 1 回 + resolved=1 ログ"
else
  fail "シナリオ 2 失敗: rc=$rc, mutation=$(mutation_count)"
  cat "${TMP_DIR}/stdout"
fi

# ============================================================
# シナリオ 3: 1 件 + author.login が別 bot → mutation 0 回 + warning
# ============================================================
ONE_OTHER_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha","comments":[],"resolved_thread_ids":["PRRT_kwDOBBB"]}'
THREADS_OTHER="$(threads_json_with "PRRT_kwDOBBB" "coderabbitai")"
rc=$(run_script "$ONE_OTHER_PAYLOAD" "$THREADS_OTHER")
if [[ "$rc" -eq 0 ]] && [[ "$(mutation_count)" -eq 0 ]] \
   && grep -F "誤 resolve 防止のため skip" "${TMP_DIR}/stdout" > /dev/null \
   && grep -F "skipped=1" "${TMP_DIR}/stdout" > /dev/null; then
  pass "シナリオ 3: 別 bot 1 件 → mutation 0 回 + warning + skipped=1（誤 resolve 防止）"
else
  fail "シナリオ 3 失敗: rc=$rc, mutation=$(mutation_count)"
  cat "${TMP_DIR}/stdout"
fi

# ============================================================
# シナリオ 4: 1 件 + 該当 thread が GraphQL 応答に無い → mutation 0 回 + warning
# ============================================================
ONE_MISSING_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha","comments":[],"resolved_thread_ids":["PRRT_kwDOCCC"]}'
THREADS_MISSING="$(threads_json_with "PRRT_kwDOZZZ" "vibehawk-for-hirokimry")"
rc=$(run_script "$ONE_MISSING_PAYLOAD" "$THREADS_MISSING")
if [[ "$rc" -eq 0 ]] && [[ "$(mutation_count)" -eq 0 ]] \
   && grep -F "reviewThreads に見つかりません" "${TMP_DIR}/stdout" > /dev/null; then
  pass "シナリオ 4: 該当 thread 不在 → mutation 0 回 + warning"
else
  fail "シナリオ 4 失敗: rc=$rc, mutation=$(mutation_count)"
  cat "${TMP_DIR}/stdout"
fi

# ============================================================
# シナリオ 5: 複数件混在 → 該当 mutation のみ実行
# ============================================================
MIX_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha","comments":[],"resolved_thread_ids":["PRRT_OWN1","PRRT_OTHER","PRRT_OWN2","PRRT_MISSING"]}'
THREADS_MIX="$(threads_json_with \
  "PRRT_OWN1" "vibehawk-for-hirokimry" \
  "PRRT_OTHER" "github-actions" \
  "PRRT_OWN2" "vibehawk-for-hirokimry")"
rc=$(run_script "$MIX_PAYLOAD" "$THREADS_MIX")
if [[ "$rc" -eq 0 ]] && [[ "$(mutation_count)" -eq 2 ]] \
   && grep -Fx "mutation:PRRT_OWN1" "$STUB_DIR/mutation_log.txt" > /dev/null \
   && grep -Fx "mutation:PRRT_OWN2" "$STUB_DIR/mutation_log.txt" > /dev/null \
   && ! grep -F "mutation:PRRT_OTHER" "$STUB_DIR/mutation_log.txt" > /dev/null \
   && ! grep -F "mutation:PRRT_MISSING" "$STUB_DIR/mutation_log.txt" > /dev/null \
   && grep -F "resolved=2" "${TMP_DIR}/stdout" > /dev/null \
   && grep -F "skipped=2" "${TMP_DIR}/stdout" > /dev/null; then
  pass "シナリオ 5: 混在 → 自身 2 件のみ mutation、他 2 件は skip（誤 resolve なし）"
else
  fail "シナリオ 5 失敗: rc=$rc, mutation=$(mutation_count), log=$(cat "$STUB_DIR/mutation_log.txt" 2>/dev/null)"
  cat "${TMP_DIR}/stdout"
fi

# ============================================================
# シナリオ 6: 必須 env 欠落 → 非 0 終了
# ============================================================
make_gh_stub "$THREADS_EMPTY" ""
set +e
runner_temp_6="${TMP_DIR}/runner_temp_6"
mkdir -p "$runner_temp_6"
PATH="$STUB_DIR:$PATH" GH_TOKEN="x" REPO="x/y" PR_NUMBER=1 OWNER="x" \
  RUNNER_TEMP="$runner_temp_6" bash "$SCRIPT" >/dev/null 2>&1
err_rc=$?
set -e
if [[ "$err_rc" -ne 0 ]]; then
  pass "シナリオ 6: STRUCTURED_OUTPUT 未設定で非 0 終了する"
else
  fail "シナリオ 6: STRUCTURED_OUTPUT 未設定でも 0 終了してしまった"
fi

# ============================================================
# シナリオ 7: node_id 形式不一致 → mutation 0 回（入力サニタイズ動作確認）
# ============================================================
# 注: jq -r で .[] を出力するため、特殊文字を含む 1 件を 1 ID として渡す。
# 改行文字を入れると分割される（実運用で起きない異常入力）。空白・;・/ 等を含む id をテスト。
EVIL_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha","comments":[],"resolved_thread_ids":["; rm -rf /","with space","../../etc"]}'
THREADS_EVIL="$(threads_json_with "PRRT_kwDODDD" "vibehawk-for-hirokimry")"
rc=$(run_script "$EVIL_PAYLOAD" "$THREADS_EVIL")
if [[ "$rc" -eq 0 ]] && [[ "$(mutation_count)" -eq 0 ]] \
   && grep -F "GitHub node_id 形式に一致しません" "${TMP_DIR}/stdout" > /dev/null; then
  pass "シナリオ 7: node_id 形式不一致（コマンド注入文字列等） → mutation 0 回（入力サニタイズ）"
else
  fail "シナリオ 7 失敗: rc=$rc, mutation=$(mutation_count)"
  cat "${TMP_DIR}/stdout"
fi

# ============================================================
# シナリオ 8: 個別 mutation 失敗 → warning + skip、step 全体は 0 終了
# ============================================================
FAIL_PAYLOAD='{"event":"COMMENT","body":"s","commit_id":"sha","comments":[],"resolved_thread_ids":["PRRT_FAIL","PRRT_OK"]}'
THREADS_FAIL="$(threads_json_with \
  "PRRT_FAIL" "vibehawk-for-hirokimry" \
  "PRRT_OK" "vibehawk-for-hirokimry")"
rc=$(run_script "$FAIL_PAYLOAD" "$THREADS_FAIL" "PRRT_FAIL")
if [[ "$rc" -eq 0 ]] && [[ "$(mutation_count)" -eq 2 ]] \
   && grep -F "PRRT_FAIL の resolveReviewThread mutation に失敗" "${TMP_DIR}/stdout" > /dev/null \
   && grep -F "resolved=1" "${TMP_DIR}/stdout" > /dev/null \
   && grep -F "failed=1" "${TMP_DIR}/stdout" > /dev/null; then
  pass "シナリオ 8: 個別 mutation 失敗 → warning + 次に進む、step 全体は 0 終了"
else
  fail "シナリオ 8 失敗: rc=$rc, mutation=$(mutation_count)"
  cat "${TMP_DIR}/stdout"
fi

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
