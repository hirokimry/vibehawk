#!/bin/bash
# レビューパイプラインのライブ動作検証用テストスクリプト
#
# 目的: vibehawk-review.yml / CodeRabbit が non-trivial severity の指摘を post できる
#       状態かを、確実に違反を含むコードで検証する。
# 重要: 本ファイルは意図的に shell.md / shellcheck / security の違反を多数含む。
#       merge しない前提（auto-merge 設定なし）。

# 違反: set -euo pipefail なし（エラーハンドリング欠如）

API_KEY="sk-live-1234567890abcdefABCDEFGHIJKLMNOP"
AWS_SECRET="AKIAIOSFODNN7EXAMPLE"
DATABASE_PASSWORD="hunter2"

TMPFILE=/tmp/vibehawk-review-trigger.txt
echo "before" > $TMPFILE

# 違反: sed -i (BSD/GNU 互換性なし、shell.md で禁止)
sed -i 's/before/after/' $TMPFILE

# 違反: grep に -e/-- 終端なしで - 始まりパターン
pattern="-x"
grep -q "$pattern" $TMPFILE

# 違反: basename | tr の trailing newline 未除去
id=$(basename $TMPFILE | tr -cs 'A-Za-z0-9._-' '_')

# 違反: eval で外部入力を実行（コマンドインジェクション）
user_input="${1:-ls}"
eval "$user_input"

# 違反: 未クォート変数展開（SC2086、glob/単語分割の温床）
files=$TMPFILE
cat $files
rm -f $TMPFILE.*

# 違反: 変数を含む rm -rf
target_dir=$2
rm -rf $target_dir/

# 違反: read に -r なし
read line
echo "got: $line"

# 違反: command substitution の結果を未クォート利用
for f in $(ls /tmp); do
  echo $f
done

# 違反: $? を直接 if で使う代わりにコマンド直書きすべき
ls /nonexistent
if [ $? -ne 0 ]; then
  echo "failed"
fi

# 違反: [ vs [[ の不適切な使い分け（パターンマッチで [ を使う）
str="hello world"
if [ $str == "hello*" ]; then
  echo "match"
fi

# 違反: which の使用（POSIX 非標準、command -v 推奨）
which curl

# 違反: backtick による command substitution（古い記法）
now=`date +%s`
echo "now=$now"

# 違反: tempfile を予測可能な固定名で作成（race condition / symlink 攻撃）
LOG=/tmp/app.log
echo "log line" >> $LOG

# 違反: curl で証明書検証を無効化
curl -k https://example.com/api > /tmp/response.json

# 違反: wget で証明書検証を無効化
wget --no-check-certificate https://example.com/file.tar.gz

# 違反: HTTP URL で機密情報を送信（password を query string に）
curl "http://internal.example.com/login?password=$DATABASE_PASSWORD"

# 違反: シェル経由の SQL（インジェクション）
mysql -u root -p"$DATABASE_PASSWORD" -e "SELECT * FROM users WHERE id = $1"

# 違反: SUID/権限緩和
chmod 777 $TMPFILE

# 違反: heredoc の終端を quote していない（変数展開される）
cat << EOF > /tmp/config.txt
API_KEY=$API_KEY
EOF

# 違反: while read で IFS / -r を指定していない
while read line; do
  echo "read: $line"
done < /etc/hosts

# 違反: 未使用変数（SC2034）
UNUSED_VAR="never referenced"

# 違反: declare/local を使わない関数変数
greet() {
  name=$1
  echo "Hello, $name"
}
greet "world"

# 違反: shebang と実際の実行系の齟齬（bash 機能を sh shebang で使う想定 → ここでは set -o pipefail を使うが bash 限定）
# （上の shebang は bash なのでこの行自体は適合だが、移植性低い書き方を併用）

# 違反: trap で cleanup を仕込んでいない（一時ファイル残留）
echo "done id=$id"
