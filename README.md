# vibehawk

> 鷹のように観察し、追加課金ゼロで PR レビューを届ける OSS プロダクト

## 概要

vibehawk は **追加課金ゼロの PR 自動レビュー OSS プロダクト** です。利用者が既に契約している LLM サブスクリプション枠（Claude Pro / ChatGPT Plus 等）の **内側だけ** で動作し、AI レビュー専用 SaaS の月額や LLM API の従量課金を発生させません。

vibe シリーズ（vibecorp / vibemux / vibehawk）の一員として、CodeRabbit の「うさぎ（速さ・量）」に対し「鷹（精度・観察力・全体俯瞰）」のメタファーで対置します。

詳細は `MVV.md` / `docs/specification.md` / `docs/POLICY.md` を参照。

## 利用者の導入手順（3 ステップ）

### 1. `vibehawk` GitHub App をインストール

GitHub Marketplace（公開後）またはリポジトリ設定から `vibehawk` App をインストールします。App は以下の **最小権限** のみ要求します（詳細は `docs/SECURITY.md`）:

- `pull_requests: write`
- `issues: write`
- `contents: read`

### 2. workflow ファイルを配置

リポジトリに `.github/workflows/vibehawk-review.yml` を配置します。本リポジトリの同名ファイルをコピーして利用してください。

### 3. secrets を設定

リポジトリ Settings → Secrets and variables → Actions で以下を設定します:

| secret 名 | 内容 | 取得元 |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Max サブスクリプションの OAuth Token | claude-code-action 公式手順 |
| `VIBEHAWK_APP_ID` | vibehawk GitHub App ID | App 設定画面 |
| `VIBEHAWK_PRIVATE_KEY` | vibehawk GitHub App Private Key | App 設定画面で発行 |

> 3 つの secrets が揃わない状態では、workflow は起動しても自動的にスキップ動作（プレースホルダコメントのみ投稿）になります。

## ステータス

本リポジトリは **開発中**（Phase 1 基盤構築）です。Issue #7 で実行基盤を、Issue #8 以降で詳細レビュー機能（サマリコメント・inline コメント・severity 5 段階・@mention チャット応答）を順次積み上げます。
