#!/usr/bin/env bash
# 用途: bundled review の inline 指摘のうち PR の diff hunk 範囲外の行を指すものに
#       `_outside_diff: true` を付与する（Issue #281）。
#
# GitHub Reviews API は diff hunk 範囲外の行への inline コメントを受け付けず、1 件でも
# 混ざると POST 全体が 422 "Line could not be resolved" で失敗する（PR #280 で実発生）。
# 本スクリプトは PR の各ファイルの patch から「コメント可能行（RIGHT=新ファイル / LEFT=旧ファイル）」
# を算出し、範囲外を指す comment に `_outside_diff` フラグを立てる。後段の post-bundled-review.sh が
# フラグ付きを inline 投稿から外し、build-bundled-body.sh が「⚠️ Outside diff range comments」
# 本文セクションへ集約する（CodeRabbit 互換、握り潰さない）。
#
# 入力: payload JSON ファイルパス（引数 $1）を in-place で書き換える。
# env:
#   REPO / PR_NUMBER / GH_TOKEN  diff 取得用（gh api repos/<repo>/pulls/<pr>/files）
#   FILES_JSON                   テスト注入用。非空なら gh api を呼ばず本値を files 配列として使う。
#
# degrade: diff 取得に失敗したら 1 件も _outside_diff を立てず素通しする（従来挙動に戻すだけで悪化させない）。

set -euo pipefail

PAYLOAD="${1:?payload JSON ファイルパスを引数で渡してください}"
if [[ ! -f "$PAYLOAD" ]]; then
  echo "::error::mark-outside-diff: payload ファイルが存在しません: ${PAYLOAD}" >&2
  exit 1
fi

# files 配列（[{filename, patch}]）を取得する。テスト時は FILES_JSON で注入する。
files_json="${FILES_JSON:-}"
if [[ -z "$files_json" ]]; then
  : "${REPO:?REPO must be set}"
  : "${PR_NUMBER:?PR_NUMBER must be set}"
  # --paginate --slurp で全ページを配列にまとめ、add で 1 配列に連結する。
  if ! files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate --slurp --jq 'add')"; then
    echo "::warning::mark-outside-diff: PR files の取得に失敗しました。_outside_diff 判定をスキップします（従来挙動）"
    exit 0
  fi
fi

# patch を解析して「コメント可能行」の三つ組（side<TAB>path<TAB>line）を出力する。
# patch のフォーマット: `@@ -oldStart,oldCount +newStart,newCount @@` の後に
#   ' '(context) / '+'(added) / '-'(removed) / '\'(改行なし注記) の行が続く。
#   RIGHT(新ファイル)でコメント可能 = context + added の新ファイル行番号。
#   LEFT(旧ファイル)でコメント可能 = context + removed の旧ファイル行番号。
# BSD/GNU 両対応: gawk 専用の 3 引数 match() は使わず sub()+split() で hunk ヘッダを解析する（shell.md）。
triples="$(
  printf '%s' "$files_json" | jq -rc '.[] | {f: .filename, p: (.patch // "")} | select(.p != "")' \
  | while IFS= read -r row; do
      f="$(printf '%s' "$row" | jq -r '.f')"
      printf '%s' "$row" | jq -r '.p' | awk -v path="$f" '
        /^@@/ {
          minus=$2; sub(/^-/, "", minus); split(minus, mm, ","); oldline=mm[1]+0
          plus=$3;  sub(/^\+/, "", plus); split(plus, pp, ","); newline=pp[1]+0
          next
        }
        {
          c=substr($0,1,1)
          if (c=="+")      { print "RIGHT\t" path "\t" newline; newline++ }
          else if (c=="-") { print "LEFT\t"  path "\t" oldline; oldline++ }
          else if (c==" ") { print "RIGHT\t" path "\t" newline; print "LEFT\t" path "\t" oldline; newline++; oldline++ }
        }
      '
    done
)"

# 三つ組を {side: {path: [lines]}} の lookup map にする。
commentable_map="$(
  printf '%s' "$triples" | jq -R -s '
    split("\n")
    | map(select(length > 0) | split("\t"))
    | reduce .[] as $t (
        {};
        .[$t[0]][$t[1]] += [($t[2] | tonumber)]
      )
  '
)"

# diff 範囲情報が 1 件も取れなかった（map が空）場合は判定をスキップする（従来挙動に degrade）。
# 取得失敗やパース不能時に「全件 outside」と誤判定して inline を全消ししないための保険。
if [[ -z "$commentable_map" || "$commentable_map" == "{}" ]]; then
  echo "vibehawk: diff 範囲情報が得られなかったため _outside_diff 判定をスキップします（従来挙動、Issue #281）"
  exit 0
fi

# 各 comment に _outside_diff を付与する。
# outside = 行番号が取れない or side/path の commentable 集合に含まれない行が 1 つでもある。
tmp="$(mktemp "$(dirname "$PAYLOAD")/.$(basename "$PAYLOAD").XXXXXX")"
jq --argjson map "$commentable_map" '
  .comments |= ( . // [] | map(
    ($map[(.side // "RIGHT")][.path] // []) as $ok
    | ([.line, .start_line] | map(select(. != null))) as $need
    | ._outside_diff = (
        ($need | length) == 0
        or any($need[]; . as $n | ($ok | index($n)) == null)
      )
  ))
' "$PAYLOAD" > "$tmp" && mv "$tmp" "$PAYLOAD"

outside_n="$(jq '[.comments[]? | select(._outside_diff == true)] | length' "$PAYLOAD")"
echo "vibehawk: diff 範囲外の inline 指摘を ${outside_n} 件マークしました（本文の Outside diff range へ集約、Issue #281）"
