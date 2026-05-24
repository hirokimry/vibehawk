---
description: 通知文・長めのプロンプトテンプレを yaml / SKILL.md / hook 内に embed せず、個別 .md ファイルに切り出すための規範ルール（閾値 + 配置先 + 命名規約 + 例外）
paths:
  - ".github/workflows/**/*.yml"
  - ".github/workflows/**/*.yaml"
  - "hooks/**/*.sh"
  - "skills/**/SKILL.md"
---

> [!IMPORTANT]
> 通知文・長めのプロンプトテンプレは yaml / SKILL.md / hook 内に **embed しない**。
> 個別 `.md` ファイルに切り出して規定パスに配置する。
> 本ルールは **テキスト本体の切り出し** を扱う（yaml 内シェルコードの切り出しは兄弟ルール `workflow-shell.md` の管轄）。

# 📖 通知文・プロンプト切り出し基準

`.github/workflows/**/*.yml` の `--body "..."` で投稿される **CEO 向け Bot 通知文**、`skills/**/SKILL.md` 内のエージェント呼出プロンプトテンプレ、`hooks/**/*.sh` の長めのエラーメッセージを **個別 `.md` ファイルに切り出す** ことで以下を達成する。

- 規範対象ファイルが明確化（個別 `.md` = `document-writing.md` / `prompt-writing.md` の管轄）
- 既存書き換え動線（`/vibecorp:docs-rewrite-all` / `/vibecorp:prompts-rewrite-all`）が切り出された `.md` を自然に拾える
- yml / SKILL.md / sh 自体は構造のみ残り、規範チェックの対象が狭まる

挙動不変が前提（文面の意味・動作を変えずに配置のみ分離する）。

## 🎯 対象範囲

本ルールは frontmatter の `paths` で対象を絞る。

- 対象: yaml workflow / SKILL.md / hook シェルスクリプトのうち、**テキスト本体を embed しているもの**。
- 読込タイミング: 対象ファイル編集時に lazy-load。
- 公式仕様: https://code.claude.com/docs/en/memory#path-specific-rules

| 対象種別 | embed されがちな箇所 |
|---------|------------------|
| **🤖 GHA workflow** | `gh issue comment --body "..."`, `gh pr comment --body "..."`, `actions/github-script` の `script:` 等 |
| **⚙️ スキル本体** | エージェント呼出プロンプトテンプレ（` ```text ` ブロック）、長めの利用例 |
| **🪝 hook シェル** | `echo` / `cat <<EOF` で出力する CEO 向けエラー・警告文 |

## 📏 切り出し閾値

**行数軸と用途軸を併用して判定し、いずれか（OR）を満たせば切り出し対象**とする。

### 行数軸

| 種別 | 閾値 | 根拠 |
|---|---|---|
| **通知文（CEO が GitHub UI で読む文面）** | 行数 3 行以上 | `workflow-shell.md` の「3 行以上で切り出し」と整合 |
| **プロンプトテンプレ（エージェント呼出 / 長めの指示）** | 行数 5 行以上 | プロンプトはコード行より文章行が長いため閾値を緩める |
| **hook の CEO 向けエラー・警告文** | 行数 3 行以上 | 通知文と同じ扱い |

「行数」はコメント行・空行を除き、実際の文字を持つ行数で数える。

### 用途軸

行数閾値を満たさなくても、**用途**で切り出し対象になる場合がある。

| 用途 | 判定 | 例 |
|---|---|---|
| **CEO 通知文（GHA `--body`）** | 行数を問わず切り出し対象 | `gh issue comment --body "⚠️ intent ラベルが付与されていません..."` |
| **エージェント呼出プロンプトテンプレ** | 行数を問わず切り出し対象 | `Task tool で以下を依頼する: 「以下の計画をレビューしてください...」` |
| **再利用される定型文** | 2 箇所以上で使われる場合は切り出し対象 | 複数の workflow / SKILL で同じ文面が現れる |

### 判定の優先順位

1. 用途軸（CEO 通知文 / エージェント呼出 / 再利用定型文）に該当するか確認する
2. 該当しない場合は行数軸で判定する
3. **両軸とも非該当** であれば embed のまま許容する（例外節を参照）

## 📂 配置先パスの規約

切り出した `.md` ファイルは以下のパスに配置する。

| 用途 | 配置先 | 拾われる動線 |
|---|---|---|
| **GHA workflow から呼ぶ通知文** | `.github/workflows/messages/<name>.md` | `/vibecorp:docs-rewrite-all`（`document-writing.md` paths 拡張） |
| **スキルから呼ぶエージェント呼出プロンプト** | `skills/<skill>/prompts/<name>.md` | `/vibecorp:prompts-rewrite-all`（`prompt-writing.md` paths 拡張） |
| **hook から呼ぶ CEO 向け文** | `hooks/messages/<name>.md` | `/vibecorp:docs-rewrite-all`（`document-writing.md` paths 拡張） |

### 参照方法

| ファイル種別 | 参照方法 |
|---|---|
| **yaml workflow** | `gh issue comment --body-file .github/workflows/messages/<name>.md` |
| **SKILL.md** | スキル本文内で「以下のプロンプトは `skills/<skill>/prompts/<name>.md` を参照」のように相対パス記述 |
| **hook シェル** | `cat "${SCRIPT_DIR}/messages/<name>.md"`（`SCRIPT_DIR` は `dirname "${BASH_SOURCE[0]}"` で解決） |

## 📝 命名規約

切り出し先ファイル名は **用途プレフィックス + 内容スラッグ** の組合せ。

| プレフィックス | 用途 | 例 |
|---|---|---|
| `notify-` | CEO 通知文（GHA / hook） | `notify-intent-label-missing.md`, `notify-pr-issue-link-missing.md` |
| `agent-call-` | エージェント呼出プロンプトテンプレ | `agent-call-cpo.md`, `agent-call-ciso.md` |
| `error-` | エラーメッセージ（hook 等） | `error-permission-denied.md`, `error-config-not-found.md` |

### スラッグの書き方

- kebab-case（小文字 + ハイフン区切り）
- 2〜4 語
- 内容が一目で分かる名詞句（動詞起点ではない）
- 拡張子は `.md` 固定

### 命名例

```text
.github/workflows/messages/notify-intent-label-missing.md
.github/workflows/messages/notify-pr-issue-link-missing.md
.github/workflows/messages/notify-plugin-version-bump-missing.md
skills/plan/prompts/agent-call-plan-architect.md
skills/ship/prompts/agent-call-cpo-issue-check.md
hooks/messages/error-permission-denied.md
hooks/messages/notify-guide-gate-required.md
```

## 🚧 例外（切り出さない対象）

以下は **embed のまま許容** する。

| 例外 | 理由 | 例 |
|---|---|---|
| **1〜2 行の単純通知** | 切り出すと逆に追跡が困難 | `gh issue comment --body "✅ approved"` |
| **動的生成文** | 実行時に値を埋め込む文面はテンプレ化が難しい | `echo "Issue #${num} を更新しました"` のみで完結する 1〜2 行 |
| **文脈依存で意味が変わる文** | 周辺コードと一体で意味を成すもの | エラーハンドリング内の 1 行 `echo "rate limit"` |
| **エージェントログ・デバッグ出力** | CEO 向けではない開発者向け出力 | `echo "[DEBUG] start" >&2` |
| **ファイル全体が文面のみで構成されるテンプレ** | 既に `.md` 単体で存在するもの | `README.md` / `CHANGELOG.md` / `docs/**/*.md`（`document-writing.md` の管轄） |

### 例外判定の優先順位

1. 上記例外のいずれかに該当するか確認する
2. 該当する場合は embed のまま維持し、必要に応じてコード内コメントで「短文のため embed 維持」と明記する
3. 該当しない場合は切り出し対象とする

## 🔄 Before / After

### 通知文の例（GHA workflow）

#### Before（NG）

```yaml
- name: intent ラベル不在通知
  run: |
    gh issue comment "${ISSUE_NUMBER}" --body "⚠️ intent/* ラベルが付与されていません（許可 7 種のうち 1 つを付ける必要があります）。1 Issue 1 intent ルール（intent/feature, intent/bugfix, intent/performance, intent/security, intent/refactor, intent/infra, intent/docs から 1 つ）に従い、ラベルを 1 つ付与してください。詳細は .claude/rules/intent-labels.md を参照。"
```

#### After（OK）

```yaml
- name: intent ラベル不在通知
  run: gh issue comment "${ISSUE_NUMBER}" --body-file .github/workflows/messages/notify-intent-label-missing.md
```

切り出し先 `.github/workflows/messages/notify-intent-label-missing.md` には CEO 向け通知文をそのまま配置する。

### プロンプトの例（SKILL.md）

#### Before（NG）

```markdown
### エージェント起動

Task tool で以下を実行する:

\`\`\`text
.claude/agents/plan-architect.md の指示に従い、以下の計画をレビューしてください。
計画ファイル: {plan_content}
Issue 完了条件: {completion_criteria}
プロジェクトの既存コード構造: {code_overview}
\`\`\`
```

#### After（OK）

```markdown
### エージェント起動

Task tool で以下を実行する。プロンプトは `skills/plan-review-loop/prompts/agent-call-plan-architect.md` を参照する。
```

切り出し先 `skills/plan-review-loop/prompts/agent-call-plan-architect.md` には text ブロックの中身をそのまま配置する。

## ✅ 指針（MUST）

1. 📏 **閾値を満たしたら切り出す**
   - 行数軸（通知文 3 行 / プロンプト 5 行 / hook エラー 3 行）または用途軸（CEO 通知 / エージェント呼出 / 再利用定型文）のいずれか該当で切り出す。
   - 例外節に該当する場合のみ embed を許容する。

2. 📂 **規定パスに配置する**
   - `.github/workflows/messages/<name>.md` / `skills/<skill>/prompts/<name>.md` / `hooks/messages/<name>.md`。
   - 規定外パスは禁止（書き換え動線が拾えなくなる）。

3. 📝 **命名規約に従う**
   - 用途プレフィックス（`notify-` / `agent-call-` / `error-`）+ kebab-case のスラッグ 2〜4 語。
   - 拡張子は `.md` 固定。

4. 🔄 **挙動不変を守る**
   - 切り出し前後で文面の意味・実行時挙動を変えない。
   - 文言調整が必要な場合は別 Issue で扱う。

5. 🔗 **参照元から参照先が辿れる**
   - yaml 側は `--body-file <path>` で参照する。
   - SKILL.md / hook 側はファイル本文で「以下のプロンプトは `<path>` を参照」のように記述する。

## ❌ 禁止パターン

- ❌ **3 行以上の通知文を `--body "..."` に直接 embed する**
  - CEO 向け文面の所在が不明瞭になる。
- ❌ **5 行以上のプロンプトテンプレを SKILL.md 内に embed する**
  - 規範対象（`prompt-writing.md`）の管轄が混在する。
- ❌ **規定外パス（例: `.github/workflows/*.txt` / `skills/<skill>/prompts.txt`）に切り出す**
  - 書き換え動線が拾えなくなる。
- ❌ **命名規約を無視した名前（例: `body1.md` / `prompt.md`）**
  - 用途が一目で判別不能になる。
- ❌ **切り出し時に文面を変更する**
  - 挙動不変の前提を破る。文言調整は別 Issue で扱う。
- ❌ **動的生成文（実行時に値を埋め込む 1〜2 行）を無理に切り出す**
  - テンプレ化困難で逆に追跡コストが上がる。

## 🧪 テスト可能性

ルール本体は `tests/test_notification_prompt_extraction_rule.sh` で静的検証する。

- 確認対象: 中核セクション存在を grep で検出できること。

### 静的検証で確認すること

- ルールファイル本体の存在。
- frontmatter の `description` / `paths` キー存在。
- `paths` に `.github/workflows/**` / `hooks/**` / `skills/**/SKILL.md` が含まれること。
- 中核セクション見出し（切り出し閾値 / 配置先 / 命名規約 / 例外 / 禁止パターン）の存在。
- 規定パス文字列（`.github/workflows/messages/` / `skills/<skill>/prompts/` / `hooks/messages/`）の存在。
- 命名プレフィックス（`notify-` / `agent-call-` / `error-`）の存在。
- 兄弟ルール `workflow-shell.md` への相互参照の存在。

### shell.md 整合

- `grep -q -e` でパターン終端を明示。
  - 理由: `-` 始まりパターン対策。
- `set -euo pipefail` 下で前提ファイル不在時は `fail` 後に `exit 1`。
  - 理由: 後続テスト無効化防止。
- `sed -i` 不使用。
  - 理由: Bash 互換性確保。

## 🔗 兄弟ルール（workflow-shell.md との関係）

`workflow-shell.md` と本ルールは **対象が異なる兄弟ルール** であり競合しない。

| ルール | 対象 | 切り出し先 |
|---|---|---|
| `workflow-shell.md` | yaml `run:` ブロックの **シェルコード** | `.github/scripts/*.sh` |
| `notification-prompt-extraction.md`（本ルール） | yaml `--body` / SKILL.md / hook の **テキスト本体** | `.github/workflows/messages/*.md` / `skills/<skill>/prompts/*.md` / `hooks/messages/*.md` |

### 両ルールの併用例

`.github/workflows/intent-label-issue-check.yml` で 3 行以上のシェル処理が `gh issue comment --body "..."` を呼ぶ場合:

1. `workflow-shell.md` に従ってシェル本体を `.github/scripts/intent-label-check.sh` に切り出す。
2. 本ルールに従って `gh issue comment --body-file .github/workflows/messages/notify-intent-label-missing.md` に切り出す。
3. workflow yaml 側には 1〜2 行の呼び出しのみ残る。

両者を併用することで yaml は **構造のみ** が残り、コード本体は `.sh`、テキスト本体は `.md` に分離される。

## 🔗 関連ルール

- 兄弟ルール（コード切り出し）: `workflow-shell.md`
- ベース基準（全 .md 共通）: `document-writing.md`
- プロンプト系拡張: `prompt-writing.md`
- CEO 向け文面規約: `communication.md`
- 配置・言語規約: `documentation.md`
- マークダウン規約（フェンスコードブロック言語指定義務）: `markdown.md`

## 📂 関連ファイル

- `tests/test_notification_prompt_extraction_rule.sh`（本ルールの静的検証）
- `tests/test_distribution_notification_prompt_extraction.sh`（本ルールの配布同期検証）
- `.github/workflows/messages/`（切り出し先、子3 #640 で本体セルフ適応）
- `skills/<skill>/prompts/`（切り出し先、子4 #642 で本体セルフ適応）
- `hooks/messages/`（切り出し先、子3 #640 で本体セルフ適応）
