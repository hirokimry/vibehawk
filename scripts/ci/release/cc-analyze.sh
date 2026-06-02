#!/usr/bin/env bash
# 用途: Conventional Commits を解析し semver bump レベルとリリースノートを算出する共有ライブラリ（Issue #307）
#
# source して `cc_analyze <git-range>` を呼ぶと以下のグローバルを設定する:
#   CC_BUMP_LEVEL    : 0=none / 1=patch / 2=minor / 3=major
#   CC_RELEASE_NOTES : カテゴリ別 markdown リリースノート（末尾改行付き、空なら空文字）
#
# bump マッピング（標準 semver）:
#   BREAKING（`type!:` または body の `BREAKING CHANGE:`） → major(3)
#   feat                                                   → minor(2)
#   fix / perf / revert                                    → patch(1)
#   refactor / docs / style / test / ci / chore / build    → bump なし(0、ノートには載せる)
#
# `bump_version <current> <level>` で算出済み level から次バージョン文字列を返す。
#
# 絵文字プレフィックス付き CC タイトル（例 `📖 docs: ...`）でも type を抽出できる。

# 多重 source 防止
if [[ -n "${VIBEHAWK_CC_ANALYZE_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
VIBEHAWK_CC_ANALYZE_LOADED=1

# CC_BUMP_LEVEL / CC_RELEASE_NOTES は source 元（呼び出し側）が参照する出力グローバル。
# shellcheck disable=SC2034
cc_analyze() {
  local range="$1"
  CC_BUMP_LEVEL=0
  CC_RELEASE_NOTES=""

  local commits
  # %x1f = unit separator（フィールド区切り）, %x1e = record separator（コミット区切り）
  commits=$(git log --pretty=format:'%s%x1f%H%x1f%h%x1e' "$range")

  local feat="" fix="" perf="" refactor="" docs="" other="" breaking=""

  local subject full_hash short_hash
  while IFS=$'\x1f' read -r -d $'\x1e' subject full_hash short_hash; do
    # `git log --pretty=format:` はレコード間に改行を挟むため、2 件目以降の subject 先頭に
    # 付く改行を除去する（残すとリリースノートの説明文が改行で割れる）。
    subject="${subject#$'\n'}"
    [[ -z "$subject" ]] && continue

    local body is_breaking clean type desc
    body=$(git log -1 --pretty=format:'%b' "$full_hash")
    is_breaking=false
    if printf '%s' "$subject" | grep -qE '^[^:]*!:' || printf '%s' "$body" | grep -q -- 'BREAKING CHANGE:'; then
      is_breaking=true
    fi

    # 先頭の非英字（絵文字・空白）を除去してから type を抽出する
    clean=$(printf '%s' "$subject" | sed 's/^[^a-zA-Z]* *//')
    type=$(printf '%s' "$clean" | sed -n 's/^\([a-zA-Z]*\)\(([^)]*)\)\{0,1\}[!]\{0,1\}:.*/\1/p')
    desc=$(printf '%s' "$subject" | sed 's/^[^:]*: *//')

    if [[ "$is_breaking" == true ]]; then
      [[ "$CC_BUMP_LEVEL" -lt 3 ]] && CC_BUMP_LEVEL=3
      breaking="${breaking}- ${desc} (${short_hash})"$'\n'
    fi

    case "$type" in
      feat)
        [[ "$CC_BUMP_LEVEL" -lt 2 ]] && CC_BUMP_LEVEL=2
        feat="${feat}- ${desc} (${short_hash})"$'\n'
        ;;
      fix)
        [[ "$CC_BUMP_LEVEL" -lt 1 ]] && CC_BUMP_LEVEL=1
        fix="${fix}- ${desc} (${short_hash})"$'\n'
        ;;
      perf)
        [[ "$CC_BUMP_LEVEL" -lt 1 ]] && CC_BUMP_LEVEL=1
        perf="${perf}- ${desc} (${short_hash})"$'\n'
        ;;
      revert)
        # 差し戻しは regression 修正の一形態なので patch 扱いにし、バグ修正ノートに載せる
        [[ "$CC_BUMP_LEVEL" -lt 1 ]] && CC_BUMP_LEVEL=1
        fix="${fix}- ${desc} (${short_hash})"$'\n'
        ;;
      refactor)
        refactor="${refactor}- ${desc} (${short_hash})"$'\n'
        ;;
      docs)
        docs="${docs}- ${desc} (${short_hash})"$'\n'
        ;;
      *)
        # style / test / ci / chore / build / CC 非準拠は bump せず「その他」に蓄積する
        other="${other}- ${desc:-$subject} (${short_hash})"$'\n'
        ;;
    esac
  done < <(printf '%s' "$commits")

  local notes=""
  [[ -n "$breaking" ]] && notes="${notes}## ⚠️ 破壊的変更"$'\n'"${breaking}"$'\n'
  [[ -n "$feat" ]] && notes="${notes}## ✨ 新機能"$'\n'"${feat}"$'\n'
  [[ -n "$fix" ]] && notes="${notes}## 🐛 バグ修正"$'\n'"${fix}"$'\n'
  [[ -n "$perf" ]] && notes="${notes}## ⚡ 性能改善"$'\n'"${perf}"$'\n'
  [[ -n "$refactor" ]] && notes="${notes}## 🔄 リファクタリング"$'\n'"${refactor}"$'\n'
  [[ -n "$docs" ]] && notes="${notes}## 📖 ドキュメント"$'\n'"${docs}"$'\n'
  [[ -n "$other" ]] && notes="${notes}## 🔧 その他"$'\n'"${other}"$'\n'
  CC_RELEASE_NOTES="$notes"
}

bump_version() {
  local cur="$1" level="$2"
  local major minor patch
  IFS=. read -r major minor patch <<< "$cur"
  case "$level" in
    3) printf '%s\n' "$((major + 1)).0.0" ;;
    2) printf '%s\n' "${major}.$((minor + 1)).0" ;;
    1) printf '%s\n' "${major}.${minor}.$((patch + 1))" ;;
    *) printf '%s\n' "$cur" ;;
  esac
}
