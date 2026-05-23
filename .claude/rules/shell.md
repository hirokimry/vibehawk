# 🐚 シェルスクリプト共通規約

> [!IMPORTANT]
> シェルスクリプトは **BSD/GNU 両環境で動かす**（`sed -i` 禁止、`grep -e` でパターン終端明示）。
> ユーザー入力のコマンド判定は **必ず正規化** する（環境変数プレフィックス・ラッパー・パスの除去）。
> macOS の **bash 3.2 マルチバイト** 制約に従い、変数展開は `${...}` で囲む。

シェルスクリプトで遭遇しやすい移植性・正規化・パース系のハマりどころを集約した規約。フック / テスト / `.github/scripts/` 配下スクリプトを書く際の共通基盤として用いる。

## 📜 YAML パース

- `grep -A N` で固定行数を取るとセクション境界を越えて別キーの値を巻き込む
- `awk` でブロック単位（次のトップレベルキーで停止）に抽出する

## 🛡️ コマンド判定（フック内）

ユーザー入力のコマンド文字列を判定する際は以下を正規化する。

- 環境変数プレフィックス（`KEY=VALUE ...`）の除去
- ラッパーコマンド（`env`, `command`）の除去
- 絶対パス / 相対パスを `basename` で正規化

正規化せずに文字列比較すると簡単にバイパスされる。

## 🔍 `grep` で `-` 始まりのパターンを検索する場合

- `grep -q "$pattern"` で `$pattern` が `-` 始まりだと、grep がパターンをオプションと誤認する
  - 例: `grep -q "- architect" file` は `-` を未知のオプションとしてエラーになる
- **必ず `-e` または `--` でパターン終端を明示する**:
  - `grep -q -e "$pattern" "$path"`
  - `grep -q -- "$pattern" "$path"`
- 共通のアサート関数（`assert_file_contains` 等）で任意のパターンを受ける場合は特に必須

## 🚫 `sed -i` を使わない（BSD/GNU 互換）

`sed -i` は macOS (BSD) と Linux (GNU) で引数の形式が異なり、移植性がない。

- GNU: `sed -i 's/old/new/' file`
- BSD: `sed -i '' 's/old/new/' file`

クロスプラットフォームで動作させるには、対象ファイルと同一ディレクトリで一時ファイルを作るパターンを使う。

```bash
# 推奨パターン: 対象ファイルと同一ディレクトリに一時ファイルを作成してから置換
# （同一ファイルシステムなので mv が原子的に動作する）
tmp="$(mktemp "$(dirname "$file")/.${file##*/}.XXXXXX")"
sed 's/old/new/' "$file" > "$tmp" && mv "$tmp" "$file"
```

`sed -i` はスクリプト内で **使用禁止** とする。

## 🪝 jq フィルタでのフック名マッチング

- `settings.json` のフックエントリから hook 名を抽出する際は、`.command` フィールドのパス末尾（basename）を使う
- パス文字列の前方一致で判定するとディレクトリ構造の変更に弱い
- `split("/") | last` で basename を取り出し、`.sh` 拡張子を除去してから比較する

## 🧹 ファイル名に外部入力を使う場合

- ユーザー入力値をファイルパスに組み込む前にサニタイズする
- 許可文字以外を置換する（例: `tr -cs 'A-Za-z0-9._-' '_'`）
- 未設定時のフォールバック値を必ず用意する

## 📄 `gh api` のページネーション

- リスト系エンドポイント（comments, reviews 等）は `--paginate` を付ける
- 未指定だと最初の 30 件のみ返り、以降が欠落する

## ✂️ コマンドのセグメント分割（quote-aware）

- `&&` や `;` でコマンドを分割する際は、quote 内の区切り文字を無視しなければならない
- `sed 's/&&/\n/g; s/;/\n/g'` は quote（`'...'`・`"..."`）の内外を区別しないため禁止
  - 例: `awk '/^key:/ { sub(/^key:/, ""); print; exit }' file` を分割すると `;` の位置で誤切断される
- awk で `in_single` / `in_double` フラグを管理して quote 内をスキップするか、対象外コマンドを early-exit で弾く方式を使う

```bash
# 推奨パターン: awk による quote-aware セグメント分割
echo "$cmd" | awk '
BEGIN { in_s=0; in_d=0; seg="" }
{
  n = split($0, chars, "")
  for (i = 1; i <= n; i++) {
    c = chars[i]
    if (c == "'"'"'" && !in_d) { in_s = !in_s }
    else if (c == "\"" && !in_s) { in_d = !in_d }
    else if (!in_s && !in_d) {
      if (c == ";" || (c == "&" && chars[i+1] == "&")) {
        print seg; seg = ""
        if (c == "&") i++
        continue
      }
    }
    seg = seg c
  }
  if (seg != "") print seg
}'
```

## 🍎 bash 3.2（macOS デフォルト）でのマルチバイト文字と変数展開

- macOS のデフォルト bash は 3.2 であり、UTF-8 マルチバイト文字を変数名境界として扱えない
- `$status（` のように変数の直後に全角文字（例: `（` = `EF BC 88`）が続くと、bash 3.2 が UTF-8 バイト列を変数名の一部として解釈し unbound variable エラーになる
  - 例: `echo "ステータス: $status（完了）"` → `status\xef\xbc\x88: unbound variable`
- **変数展開には必ずブレース `${}` を使う**:
  - 🔴 NG: `$status（完了）`
  - 🟢 OK: `${status}（完了）`
- テストスクリプト・フックスクリプトは macOS の bash 3.2 で動作確認が必要

## 🔚 `basename` の出力を `tr` に渡す場合は trailing newline を除去する

`basename "$path" | tr -cs 'A-Za-z0-9._-' '_'` は `basename` が出力する末尾の `\n` も `_` に変換してしまい、結果の末尾に余分な `_` が付く。

**`printf '%s'` でコマンド置換し、trailing newline を除去してから `tr` に渡す**。

```bash
# 🔴 NG: basename の trailing newline が _ に変換されて末尾に付く
id="$(basename "$root" | tr -cs 'A-Za-z0-9._-' '_')"

# 🟢 OK: printf で newline を剥がしてから tr に渡す
id="$(printf '%s' "$(basename "$root")" | tr -cs 'A-Za-z0-9._-' '_')"
```

ファイル名サニタイズや ID 生成など、コマンド置換の出力を `tr` に渡すパターン全般に適用する。

## 🔗 関連ルール

- workflow yaml のインラインシェル切り出しルール: `workflow-shell.md`
- テスト追加義務: `testing.md`
- マークダウン規約（フェンスコードブロック言語指定）: `markdown.md`
