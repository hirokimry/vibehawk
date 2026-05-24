# scripts/ci/

`.github/workflows/` 配下のインライン shell から切り出した CI 用シェルスクリプト群。

## 目的

- yaml の `run: |` ブロック内に直書きされたシェルロジックを `.sh` ファイルとして外出しする
- 単体テスト（`tests/test_*.sh`）と shellcheck を効かせる
- 別 workflow / ローカルから同じロジックを再利用できるようにする

エピック #174「yaml インライン shell 抽出」で導入された。

## ディレクトリ構成

```text
scripts/
  ci/
    README.md              # 本ファイル
    common/
      log.sh               # 統一ログフォーマット
      gh-helpers.sh        # gh CLI ラッパー（--paginate 強制）
      jq-helpers.sh        # jq ヘルパー（string interpolation 禁止規約準拠）
    <workflow-name>/       # 切り出し先（例: vibehawk-review/, vibehawk-chat/）
      <step-name>.sh       # workflow の各ステップ相当のスクリプト
```

`<workflow-name>/` 配下は後続 Issue（#176〜#180）で順次追加される。本 Issue #175 では `common/` と本 README、shellcheck CI のみを整備する。

## 運用規約

### スクリプト本体

- 1 ファイル目の冒頭は必ず `#!/usr/bin/env bash` + `set -euo pipefail` から始める
- 引数より環境変数経由の入力を推奨（workflow の `env:` セクションと整合させやすい）
- 副作用（gh API 呼び出し、ファイル作成等）は関数化し、`main` 関数から呼ぶ構造を推奨
- 共通ヘルパー（`common/*.sh`）を使うときは相対パスの `source` ではなく、`scripts/ci/common/<name>.sh` を `dirname "${BASH_SOURCE[0]}"` 基準で読み込む

### 呼び出し規約

workflow から呼ぶときは以下の形式に統一する:

```yaml
- name: <ステップ名>
  env:
    INPUT_FOO: ${{ github.event.foo }}
    INPUT_BAR: ${{ secrets.BAR }}
  run: bash scripts/ci/<workflow-name>/<step-name>.sh
```

`run: |` の中に長いシェルを書かず、ラッパー呼び出しのみに留める（エピック #174 の完了基準: `run:` ブロックは 5 行以下のラッパー呼び出しのみ）。

### shellcheck 規約

- `scripts/ci/**/*.sh` と `tests/test_*.sh` は CI ジョブ `shellcheck`（`.github/workflows/shellcheck.yml`）で走査される
- `--severity=warning` で fail させる
- 例外的に warning を抑制する場合は `# shellcheck disable=SCxxxx` を該当行の直前に付け、**理由をコメントで併記する**
- ファイル全体での抑制（先頭での `# shellcheck disable=...`）は原則禁止
- `scripts/ci/**/*.sh` には除外ルールなし（strict）。`tests/test_*.sh` のみ `SC2089` / `SC2090`（既存 JSON literal export パターンに対する false positive）を `--exclude` で除外している。新規スクリプトでは `export VAR='value'` 形式（assign + export を 1 行に統合）を推奨し、本除外に依存しないこと

## tests/ との連携

切り出し先のシェルには対応する単体テストを `tests/test_<対象>.sh` として配置する（`.claude/rules/testing.md` 準拠）。標準的な呼び出しパターン:

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 共通ヘルパーを source して、シェル単位で動作確認する
source "${REPO_ROOT}/scripts/ci/common/log.sh"

# 対象スクリプトを実行（環境変数で入力を渡す）
INPUT_FOO=test bash "${REPO_ROOT}/scripts/ci/<workflow-name>/<step-name>.sh"
```

`tests/test_*.sh` 自体は `.github/workflows/test.yml` で自動実行されるため、新しいスクリプトを追加したらテストも同時に追加すれば CI が自動的に検証する。

## 共通ヘルパー

### `common/log.sh`

- `log_info <msg>` — INFO レベル、stdout
- `log_warn <msg>` — WARN レベル、stderr
- `log_error <msg>` — ERROR レベル、stderr

INFO は stdout、WARN/ERROR は stderr に分けて出力する（CI ログ上で問題箇所を見つけやすくする）。

### `common/gh-helpers.sh`

- `gh_api_paginated <endpoint> [jq_filter]` — `gh api --paginate` のラッパー。リスト系エンドポイントで 30 件以降が欠落しないことを保証する（`.claude/rules/shell.md`）
- `gh_issue_field <issue_number> <field_name>` — `gh issue view --json <field> --jq '.<field>'` のラッパー

### `common/jq-helpers.sh`

- `jq_concat <part1> [<part2> ...]` — 文字列を jq の `+` で結合する（`\(...)` string interpolation は使わない、`/vibecorp:ship` SKILL.md 制約より）
- `jq_obj_set_str <json_object> <key> <string_value>` — 既存 JSON オブジェクトに文字列キーを追加する

#### なぜ string interpolation `\(...)` を使わないか

`jq -n --arg n "$count" '"件数: \($n)"'` のように書くと、Bash 上で `\` がエスケープ文字、`()` がサブシェルとして解釈され、意図しない展開やパースエラーを引き起こす。代わりに `+` で結合する:

```bash
jq -n --arg prefix "件数: " --arg n "$count" '$prefix + $n'
```

## 関連

- 親エピック: #174
- 既存ルール: `.claude/rules/testing.md`（テスト規約）
- 既存ルール: `.claude/rules/shell.md`（シェル定石）
- shellcheck CI: `.github/workflows/shellcheck.yml`
