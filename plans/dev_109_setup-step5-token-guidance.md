# Issue #109 実装計画: setup ウィザード Step 5 で claude setup-token 実行ガイダンスを sandbox 環境向けに拡充する

## 概要

setup ウィザード Step 5（`CLAUDE_CODE_OAUTH_TOKEN` 取得）の `claude setup-token` 案内文を、Issue #56 dogfooding で判明した 3 つの障害（Claude Code セッション内再帰起動、vibecorp alias 展開、sandbox HOME 制約）に対処できる形に拡充する。

intent: `intent/bugfix`（既存バグを最小修正で直す。案内文の追加のみ、Step 5 のロジックは不変）。

## 影響範囲

| ファイル | 変更内容 | 行範囲（変更前） |
|---|---|---|
| `cli/oauth.js` | `promptToken()` のガイダンス文に「別ターミナル / alias バイパス / HOME 外 cd / 再帰起動注意 / 代替経路」を追加 | 34-56 |
| `cli/oauth.js` | `printRegistrationInstructions()` 内 line 161 の再取得案内文の補足 | 161 |
| `cli/setup.js` | `showClipboardFallback()` 内 line 198 の再取得案内文の補足 | 198 |
| `tests/test_setup_wizard.sh` | promptToken のガイダンス文字列に必要キーワードが含まれることを検証 | 末尾追記 |

### Step 5 と他ステップの境界（後続 #111 競合判定材料）

- 直前 #116 は Step 2 のみを変更しており、Step 5 とは行ベースで分離されている
- 本 PR (#109) で変更する Step 5 関連の範囲:
  - `cli/setup.js:137-160` (secret-token ステップ定義) — **触らない**（ロジック不変）
  - `cli/setup.js:198` (showClipboardFallback 内の Step 5 再取得案内文 1 行) — **触る**
  - `cli/oauth.js:34-56` (promptToken のガイダンス文) — **触る**（主修正）
  - `cli/oauth.js:143-168` (printRegistrationInstructions の line 161 周辺) — **触る**（補足）
- 後続 #111 が触る予定の Step 5/6: secret-token の verify 経路 / workflow ステップ（`cli/setup.js:161-181` 周辺）。本 PR は **案内文のみ** 変更し、verify ロジック・workflow ステップには触れない

## Phase 1: cli/oauth.js promptToken ガイダンス拡充

`cli/oauth.js:34-56` の `promptToken()` 出力を以下の構造に変更する:

1. 見出し「Claude OAuth Token の取得」（既存維持）
2. 推奨手順ブロック:
   - **別ターミナル** を開く（Claude Code 内 `!` 経由は不可）
   - HOME 外（例: `/tmp`）に `cd` する
   - alias を回避するため `\claude` または `command claude` を使う
   - 推奨コマンド例: `cd /tmp && \claude setup-token`
3. 注意書きブロック:
   - Claude Code セッション内で `!claude setup-token` を実行すると Claude Code が **再帰的に新規起動** して setup-token サブコマンドが効かない
   - vibecorp 系の `alias claude='command claude --add-dir ..'` が定義されている環境では bare な `claude setup-token` が alias 展開で通常起動モードになる
   - vibehawk sandbox 等で WORKTREE が HOME 配下と判定される環境では HOME 外（`/tmp` 等）で実行する
4. 代替経路:
   - token 取得に失敗した場合は Anthropic Console (https://console.anthropic.com/settings/keys) で API key を発行する手順をリンクで案内
5. token 入力プロンプト（既存維持）

文字列の構築は既存の `console.log` 多用パターンに合わせる。

## Phase 2: cli/oauth.js printRegistrationInstructions / cli/setup.js showClipboardFallback の補強

- `cli/oauth.js:161` の「再取得が必要な場合は `claude setup-token` を再実行」を「別ターミナルで `\claude setup-token`（alias 回避）を再実行」に置換
- `cli/setup.js:198` の同等文も同様に置換

## Phase 3: tests/test_setup_wizard.sh への検証追加

`tests/test_setup_wizard.sh` 末尾に Step 5 ガイダンス検証ブロックを追加。`cli/oauth.js` を grep して以下が含まれることを確認:

- `別ターミナル`
- `\\claude setup-token` または `command claude setup-token`
- `cd /tmp`
- `再帰`（Claude Code 内 `!claude setup-token` 注意）
- `console.anthropic.com`（代替経路）

## Phase 4: 動作確認

- `node -e "require('./cli/oauth')"` で構文エラーがないこと
- `bash tests/test_setup_wizard.sh` の全テストが pass すること
- `node cli/index.js help` が引き続き動作すること

## 懸念事項

- **挙動不変性**: bugfix だが「ユーザーへの案内文の改善」のみで、関数の戻り値・呼び出しシーケンスは不変
- **既存テストへの影響**: test_setup_wizard.sh は `setup-token` 文字列を直接 grep していないので影響なし
- **API 後方互換**: `promptToken({ rlFactory })` のシグネチャは変えない

## 完了条件マッピング

- [x] cli/setup.js Step 5 ガイダンス（実体は cli/oauth.js）に「別ターミナル / alias バイパス / HOME 外 cd」3 ポイント明示
- [x] 例コマンド `cd /tmp && \claude setup-token` 提示
- [x] 「Claude Code 内 `!claude setup-token` は再帰起動」注意書き
- [x] token 取得失敗時の代替経路（Anthropic Console / API key 経路）への案内
