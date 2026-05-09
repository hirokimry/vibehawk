# vibehawk

> 鷹のように観察し、追加課金ゼロで PR レビューを届ける OSS プロダクト

## 概要

vibehawk は **追加課金ゼロの PR 自動レビュー OSS プロダクト** です。利用者が既に契約している LLM サブスクリプション枠（Claude Pro / Max 等）の **内側だけ** で動作し、AI レビュー専用 SaaS の月額や LLM API の従量課金を発生させません。

vibe シリーズ（vibecorp / vibemux / vibehawk）の一員として、CodeRabbit の「うさぎ（速さ・量）」に対し「鷹（精度・観察力・全体俯瞰）」のメタファーで対置します。

詳細は `MVV.md` / `docs/specification.md` / `docs/POLICY.md` を参照。

## 利用者の導入手順（3 ステップ）

利用者が設定する secret は **`CLAUDE_CODE_OAUTH_TOKEN` 1 個のみ**。CEO の GitHub App Private Key を配布する必要がない設計です。

### 1. workflow ファイルを配置

リポジトリに `.github/workflows/vibehawk-review.yml` を配置します。本リポジトリの同名ファイルをコピーして利用してください。workflow は以下の **最小権限** のみ要求します（詳細は `docs/SECURITY.md`）:

- `pull_requests: write`
- `issues: write`
- `contents: read`

### 2. secret を 1 個だけ設定

リポジトリ Settings → Secrets and variables → Actions で以下を設定します:

| secret 名 | 内容 | 取得元 |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Pro / Max サブスクリプションの OAuth Token | claude-code-action 公式手順（`/install-github-app` 等） |

`secrets.GITHUB_TOKEN` は GitHub Actions が自動発行するため、利用者が設定する必要はありません。

### 3. PR を出す

PR を作成すると `vibehawk-review.yml` が起動し、`github-actions[bot]` 名義でレビューサマリコメントを投稿します。

> 投稿者表示について: 投稿者は `github-actions[bot]` になります。`vibehawk[bot]` ブランド表示は OSS 配布性（Private Key 非配布）とのトレードオフで Issue #22 にて妥協されました。詳細は `docs/SECURITY.md` の「認証経路の設計」セクションを参照。

> `CLAUDE_CODE_OAUTH_TOKEN` 未設定の場合、workflow は起動してもプレースホルダコメントのみ投稿してスキップ動作になります。

## CLI（オプション）

`vibehawk-for-<owner>[bot]` 名義での投稿などブランド表示を希望する利用者は、`npx vibehawk install` で利用者自身の GitHub App を作成できます（v2 拡張ルート、Issue #25 以降で順次実装）。

> **対応 OS**: macOS / Linux / Windows（PowerShell / CMD / Git Bash）。Windows では `cmd /c start` でブラウザを起動します。CI で windows-latest runner で全テスト通過を保証しています。

```bash
npx vibehawk install --owner <your-github-username>
```

このコマンドは:

- ローカルに一時 HTTP サーバー（localhost:8765）を起動
- ブラウザで GitHub App Manifest Flow を開始
- vibehawk 運営側のサーバーには一切通信しない（localhost のみで完結）
- Private Key は CLI が画面に印字せず破棄（CISO Critical 条件）

### `--dry-run` モード

実行内容を事前確認したい場合は `--dry-run` を付けてください。実際には何もせず、起動する HTTP サーバーのポート・通信先・書き込み範囲を表示するだけです:

```bash
npx vibehawk install --owner alice --dry-run
```

### `setup-token` コマンド

`CLAUDE_CODE_OAUTH_TOKEN` の取得を補助し、GitHub Settings UI への登録手順を画面誘導するヘルパー:

```bash
npx vibehawk setup-token --repo alice/my-repo
```

別ターミナルで `claude setup-token` を実行してトークンを取得し、CLI のプロンプトに貼り付けます。CLI は受け取ったトークンを **GitHub Secrets に書き込みません**（Issue #72 決定、`docs/secrets-handling.md` 参照）。代わりに以下を行います:

1. 利用者の明示同意を得てから OS ネイティブのクリップボード（macOS: `pbcopy` / Linux: `xclip` 等 / Windows: `clip`）に **stdin 経由で** トークンをコピー（プロセス引数・環境変数には出さない）
2. 対象リポジトリの GitHub Settings URL（`Settings → Secrets and variables → Actions → New repository secret`）と登録手順を画面表示
3. 利用者がブラウザでその URL を開いて手動登録する

vibehawk はトークンをローカルファイルに保存せず、メモリ上のみで保持し、本プロセス終了と同時に消去します。

デフォルト導入手順（上記）では CLI は不要です。`secrets.GITHUB_TOKEN` で完結します。

## ステータス

本リポジトリは **開発中**（Phase 1 基盤構築 + OSS 配布対応）です。Issue #7 で実行基盤を、Issue #22 で OSS 配布可能化を、Issue #24 で `npx vibehawk install` 基盤を、Issue #8 以降で詳細レビュー機能（サマリコメント・inline コメント・severity 5 段階・@mention チャット応答）を順次積み上げます。
