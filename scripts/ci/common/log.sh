#!/usr/bin/env bash
# scripts/ci/common/log.sh
#
# CI スクリプト用の統一ログフォーマット。
# `log_info` / `log_warn` / `log_error` を提供する。
#
# - INFO は stdout、WARN / ERROR は stderr に出力する（CI ログ上で stderr/stdout
#   を分けたい場合に有用）
# - プレフィックスは `[INFO] ` / `[WARN] ` / `[ERROR] ` で固定する
# - 呼び出し側は `source scripts/ci/common/log.sh` してから使用する
#
# 使用例:
#   source "$(dirname "$0")/../common/log.sh"
#   log_info "処理を開始します"
#   log_warn "設定値がデフォルトにフォールバックしました"
#   log_error "必須環境変数が未設定です"

# 多重 source 防止（既に読み込み済みなら何もしない）
if [[ -n "${VIBEHAWK_CI_LOG_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
VIBEHAWK_CI_LOG_LOADED=1

# INFO レベルログ。stdout に出力する。
log_info() {
  printf '[INFO] %s\n' "$*"
}

# WARN レベルログ。stderr に出力する。
log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

# ERROR レベルログ。stderr に出力する。
# 呼び出し側で `exit` させる責務は本関数が持たない（呼び出し側が判断する）。
log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}
