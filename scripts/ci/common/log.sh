#!/usr/bin/env bash
# 用途: CI スクリプト用の統一ログフォーマット（INFO → stdout / WARN・ERROR → stderr）
#
# INFO / WARN / ERROR を stderr/stdout に分けることで CI ログのフィルタリングが可能になる。
#
# 使用例:
#   source "$(dirname "$0")/../common/log.sh"
#   log_info "処理を開始します"
#   log_warn "設定値がデフォルトにフォールバックしました"
#   log_error "必須環境変数が未設定です"

# 多重 source 防止
if [[ -n "${VIBEHAWK_CI_LOG_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
VIBEHAWK_CI_LOG_LOADED=1

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

# exit は呼び出し側の責務（このまま処理を続けるか止めるかは文脈による）
log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}
