# 🐚 workflow yaml シェル切り出しルール

> [!IMPORTANT]
> GitHub Actions の workflow yaml には **3 行以上のシェル処理を書かない**。
> `.github/scripts/<name>.sh` に切り出し、対応する `tests/test_<name>.sh` を必ず追加する。
> 切り出したスクリプトは `shell.md` 全項に準拠する。

GitHub Actions の workflow yaml で `run:` ブロックがインライン肥大化するのを防ぎ、テスト可能なシェルスクリプトとして `.github/scripts/` 配下に切り出すための規約を定める。

## 🎯 対象

- `.github/workflows/*.{yml,yaml}` の `run:` および `run: |` ブロック
- composite action（`action.yml`）の `runs.steps[].run`

## ✅ ルール

| # | 項目 | 内容 |
|---|------|------|
| 1 | 切り出し境界 | `run:` の中身が **3 行以上** になる場合は `.github/scripts/<name>.sh` に切り出す |
| 2 | 切り出し先 | `.github/scripts/<name>.sh`（kebab-case、`.sh` 拡張子、shebang `#!/bin/bash` または `#!/usr/bin/env bash`） |
| 3 | テスト追加義務 | 切り出した各スクリプトに対応する `tests/test_<name>.sh` を追加する（`testing.md` 準拠） |
| 4 | shell.md 準拠 | 切り出したスクリプトは `shell.md`（BSD/GNU 互換、`grep -e`、bash 3.2 マルチバイト、`sed -i` 禁止等）を全て満たす |
| 5 | 引数渡し | workflow 側からは環境変数または引数で値を渡し、スクリプト本体に GitHub Actions 固有の式（`${{ ... }}`）を書かない |

## 📏 インライン許容の境界

次のいずれかに該当する `run:` はインラインのまま許容する。

- **1〜2 行**の単純コマンド（`run: bash tests/test_foo.sh`、`run: npm ci` 等）
- 単一コマンド + パイプ・リダイレクト 1 段（`run: jq -r '.version' package.json > version.txt`）
- `actions/checkout@v4` などの公式 action の前後で必要となる 1 行の補助コマンド

### 🧭 判定の優先順位

1. 行数を数える（コメント・空行を除き **コマンド行が 3 行以上** なら切り出し対象）
2. ループ・条件分岐（`for` / `if` / `case` / `while`）が含まれるなら **行数を問わず切り出し対象**
3. heredoc（`<<EOF` / `<<-EOF`）が含まれるなら **行数を問わず切り出し対象**

## ❌ 禁止パターン

- ❌ `run: |` ブロック内に **3 行以上** のシェル処理を直接書く
- ❌ `run: |` 内に `for` / `if` / `case` / `while` を書く
- ❌ `run: |` 内で heredoc を使う
- ❌ 切り出したスクリプトのテストを `tests/` に書かない
- ❌ workflow 側から `${{ ... }}` をスクリプト本文に直接埋め込む（環境変数経由で渡す）

## 🔁 Before / After

### 🔴 Before（NG）

```yaml
- name: バージョン整合チェック
  run: |
    current=$(jq -r '.version' package.json)
    expected=$(git show origin/main:package.json | jq -r '.version')
    if [ "$current" != "$expected" ]; then
      echo "version mismatch: ${current} vs ${expected}"
      exit 1
    fi
```

### 🟢 After（OK）

```yaml
- name: バージョン整合チェック
  env:
    BASE_REF: ${{ github.base_ref }}
  run: bash .github/scripts/check-plugin-version-bump.sh "$BASE_REF" "HEAD"
```

切り出し先 `.github/scripts/check-plugin-version-bump.sh` は `shell.md` に準拠して書き、`tests/test_check_plugin_version_bump.sh` を追加する。

## 🛠️ 既存 `scripts/` との関係

リポジトリには既に `scripts/` 配下にスクリプトが置かれている場合がある（vibecorp 本体では `scripts/backfill-intent-labels.sh` 等）。

本ルール新設後の **新規切り出しは `.github/scripts/` を使う**。既存 `scripts/` 配下スクリプトの移動は段階移行とし、別 Issue で扱う。

## 🔗 関連ルール

- シェルスクリプト共通規約: `shell.md`
- テスト追加義務: `testing.md`
- マークダウン規約（フェンスコードブロック言語指定）: `markdown.md`
