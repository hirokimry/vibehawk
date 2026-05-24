# 用途: vibecorp 隔離レイヤの bin/ を PATH に追加する（Issue #212）
# source で実行すること（直接実行では PATH 変更が呼出元シェルに反映されない）

_vibecorp_activate() {
  local script_path
  # shellcheck disable=SC2296
  script_path="${BASH_SOURCE[0]:-${(%):-%x}}"
  local bin_abs
  bin_abs="$(cd "$(dirname "$script_path")" && pwd)"
  case ":$PATH:" in
    *":$bin_abs:"*) ;;
    *) PATH="$bin_abs:$PATH"; export PATH ;;
  esac
}
_vibecorp_activate
unset -f _vibecorp_activate
