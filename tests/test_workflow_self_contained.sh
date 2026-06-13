#!/usr/bin/env bash
# 配布 workflow の自己完結化検証（Issue #346）
#
# npx vibehawk setup が配布する workflow（vibehawk-review.yml / vibehawk-chat.yml）は
# vibehawk リポジトリ本体にしか存在しないスクリプト群を参照する。外部リポジトリでは
# pin 付き 2nd checkout（.vibehawk-runtime/）から実行する構造が壊れていないことを、
# 静的検証（runtime checkout step / 裸参照 0 件 / prefix 経由）と実行系検証
# （ランタイム解決分岐・参照先実体の存在）の両面で確認する。

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

TEMPLATES=(
  "templates/.github/workflows/vibehawk-review.yml"
  "templates/.github/workflows/vibehawk-chat.yml"
  "templates/.github/workflows/vibehawk-review-skip-mark.yml"
)

for wf in "${TEMPLATES[@]}"; do
  if [[ ! -f "$wf" ]]; then
    fail "${wf} が存在しない"
    # 前提ファイル不在 → 後続テストは全て無意味なので即終了
    echo "=== 結果: $PASSED passed, $FAILED failed ==="
    exit 1
  fi
done

echo "=== 静的検証: runtime checkout step ==="

for wf in "${TEMPLATES[@]}"; do
  # (a) 2nd checkout step が pin プレースホルダ + path + persist-credentials: false を持つ
  if grep -q -F 'repository: hirokimry/vibehawk' "$wf" \
    && grep -q -F 'ref: __VIBEHAWK_REF__' "$wf" \
    && grep -q -F 'path: .vibehawk-runtime' "$wf" \
    && grep -q -F 'persist-credentials: false' "$wf"; then
    pass "${wf}: runtime checkout step（repository / ref プレースホルダ / path / persist-credentials: false）が存在する"
  else
    fail "${wf}: runtime checkout step の必須属性が欠けている"
  fi

  # (d) hashFiles guard と GITHUB_ENV へのランタイムディレクトリ書込 step が存在する
  # guard ファイルは workflow ごとに異なる（review/chat は check-secrets.sh、
  # skip-mark は classify-paths-ignore.sh、Issue #350）。
  if grep -q -E "hashFiles\('scripts/ci/vibehawk-(review|chat|review-skip-mark)/(check-secrets|classify-paths-ignore)\.sh'\) == ''" "$wf" \
    && grep -q -F 'VIBEHAWK_RUNTIME=' "$wf" \
    && grep -q -F '>> "$GITHUB_ENV"' "$wf"; then
    pass "${wf}: hashFiles guard と VIBEHAWK_RUNTIME 解決 step が存在する"
  else
    fail "${wf}: hashFiles guard / VIBEHAWK_RUNTIME 解決 step が欠けている"
  fi
done

echo "=== 静的検証: スクリプト参照の prefix 経由 ==="

for wf in "${TEMPLATES[@]}"; do
  # (b) 裸参照（prefix なしの bash scripts/... / bash .github/scripts/...）が 0 件
  bare="$(grep -n -E 'bash (scripts/|\.github/scripts/)' "$wf" || true)"
  if [[ -z "$bare" ]]; then
    pass "${wf}: 裸のスクリプト参照が 0 件"
  else
    fail "${wf}: 裸のスクリプト参照が残っている: ${bare}"
  fi

  # (c) 全 run: 行が「prefix 経由のスクリプト実行」または「VIBEHAWK_RUNTIME 解決 step」のみ
  run_lines="$(grep -E '^[[:space:]]+run:[[:space:]]' "$wf" || true)"
  run_total="$(printf '%s\n' "$run_lines" | grep -c -v '^$' || true)"
  run_prefixed="$(printf '%s\n' "$run_lines" | grep -c -F 'bash "${VIBEHAWK_RUNTIME}/' || true)"
  run_runtime="$(printf '%s\n' "$run_lines" | grep -c -F 'VIBEHAWK_RUNTIME=' || true)"
  if [[ "$run_total" -gt 0 ]] && [[ "$run_runtime" -eq 1 ]] \
    && [[ "$run_total" -eq $((run_prefixed + run_runtime)) ]]; then
    pass "${wf}: 全 run: が prefix 経由 + 解決 step のみ（${run_prefixed}+${run_runtime}/${run_total} 件）"
  else
    fail "${wf}: prefix を経由しない run: が残っている（${run_prefixed}+${run_runtime}/${run_total} 件）"
  fi
done

echo "=== 静的検証: 配布時置換 ==="

# (e) cli/install.js が配布時にプレースホルダ置換を行う
# Issue #347: 配布時に commit SHA へ解決して置換する（renderWorkflowTemplate(wf, {...}) 呼び出し）
if grep -q -F "RUNTIME_REF_PLACEHOLDER = '__VIBEHAWK_REF__'" cli/install.js \
  && grep -q -E 'renderWorkflowTemplate\(wf' cli/install.js \
  && grep -q -F 'resolveRuntimeRefSha' cli/install.js; then
  pass "cli/install.js が配布時に __VIBEHAWK_REF__ を commit SHA へ置換する経路を持つ（Issue #347）"
else
  fail "cli/install.js のプレースホルダ置換経路が見つからない"
fi

echo "=== 実行系検証: ランタイム解決分岐（外部リポジトリ相当） ==="

# (f) hashFiles guard 相当の分岐を実行してシミュレートする。
# workflow の式 `hashFiles('<guard>') != '' && '.' || '.vibehawk-runtime'` と同じ判定を
# 「guard ファイルの存在」で再現し、外部リポジトリ（参照スクリプト不在の checkout）では
# .vibehawk-runtime、自リポジトリでは . に解決されることを検証する。
resolve_runtime() {
  # $1 = リポジトリ root（hashFiles の評価対象）, $2 = guard ファイル相対パス
  if [[ -f "$1/$2" ]]; then
    printf '.'
  else
    printf '.vibehawk-runtime'
  fi
}

EXTERNAL_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vibehawk-external-sim.XXXXXX")"
cleanup() {
  rm -rf "$EXTERNAL_ROOT" || true
}
trap cleanup EXIT

for guard in "scripts/ci/vibehawk-review/check-secrets.sh" "scripts/ci/vibehawk-chat/check-secrets.sh" "scripts/ci/vibehawk-review-skip-mark/classify-paths-ignore.sh"; do
  external_resolved="$(resolve_runtime "$EXTERNAL_ROOT" "$guard")"
  self_resolved="$(resolve_runtime "$REPO_ROOT" "$guard")"
  if [[ "$external_resolved" == ".vibehawk-runtime" ]] && [[ "$self_resolved" == "." ]]; then
    pass "guard ${guard}: 外部=.vibehawk-runtime / 自リポジトリ=. に解決される"
  else
    fail "guard ${guard}: 解決結果が不正（外部=${external_resolved} / 自=${self_resolved}）"
  fi
done

echo "=== 実行系検証: prefix 参照先の実体存在 ==="

# (g) 両テンプレートの ${VIBEHAWK_RUNTIME}/ 配下の全参照先が vibehawk リポジトリ実体に存在する
# （= pin checkout に必ず含まれる）。awk で prefix 付きパスを抽出して 1 件ずつ検証する。
for wf in "${TEMPLATES[@]}"; do
  refs="$(awk '
    {
      while (match($0, /\$\{VIBEHAWK_RUNTIME\}\/[A-Za-z0-9._\/-]+\.sh/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/^\$\{VIBEHAWK_RUNTIME\}\//, "", s)
        print s
        $0 = substr($0, RSTART + RLENGTH)
      }
    }
  ' "$wf" | sort -u)"
  if [[ -z "$refs" ]]; then
    fail "${wf}: prefix 付き参照が 1 件も抽出できない"
    continue
  fi
  missing=""
  while IFS= read -r ref; do
    if [[ ! -f "${REPO_ROOT}/${ref}" ]]; then
      missing="${missing} ${ref}"
    fi
  done <<< "$refs"
  ref_count="$(printf '%s\n' "$refs" | grep -c -v '^$' || true)"
  if [[ -z "$missing" ]]; then
    pass "${wf}: prefix 参照先 ${ref_count} 件すべてがリポジトリ実体に存在する"
  else
    fail "${wf}: prefix 参照先が実体に存在しない:${missing}"
  fi
done

echo "=== 結果: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]]
