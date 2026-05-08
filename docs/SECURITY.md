# vibehawk セキュリティポリシー

> このドキュメントはプロジェクトのセキュリティ方針を定義する Source of Truth です。

## セキュリティ方針

（セキュリティに関する基本方針を記載）

## 脆弱性報告

（脆弱性を発見した場合の報告フロー・連絡先を記載）

## 認証・認可

vibehawk は **2 系統の認証経路** を持つ。利用者リポジトリの GitHub Actions 内で完結する設計。

```text
利用者リポジトリの GitHub Actions
   ├─ ① Anthropic 認証（LLM 呼び出し）
   │     └─ CLAUDE_CODE_OAUTH_TOKEN（Claude Max 枠）または ANTHROPIC_API_KEY
   │
   └─ ② GitHub 認証（PR コメント投稿・edit・resolve）
         └─ vibehawk GitHub App の Installation Token
```

### 認証経路の設計方針

| 系統 | 採用方針 | 理由 |
|---|---|---|
| ① LLM 認証 | claude-code-action 標準の OAuth Token を流用 | Anthropic 公式経路。利用者の追加負担なし |
| ② GitHub 認証 | 独自 GitHub App `vibehawk[bot]` | 投稿者表示が `vibehawk[bot]` でブランドが立つ。サマリ識別も投稿者 ID で一意に絞れる |

### App に要求する最小権限

| 権限 | スコープ | 用途 |
|---|---|---|
| `pull_requests` | write | inline comment / サマリ投稿 / edit / approve / request_changes |
| `issues` | write | issue_comment トリガーでの @mention チャット応答 |
| `contents` | read | PR 差分の取得 |

> 注: `metadata: read` は GitHub App にデフォルトで付与される必須権限のため上記には列挙しない（明示的にリクエストする必要がない）。書き込み権限は PR と Issue コメントに限定。リポジトリのコード自体には書き込まない（5 大方針 2「コード生成しない」と整合）。

### 利用者の準備手順

| 手順 | 内容 |
|---|---|
| 1 | リポジトリに `vibehawk` GitHub App をインストール（クリック数回） |
| 2 | `.github/workflows/vibehawk.yml` を配置（テンプレートからコピペ） |
| 3 | secrets に `CLAUDE_CODE_OAUTH_TOKEN` を設定 |

→ CodeRabbit の導入手順とほぼ同じ感覚。claude-code-action と比べて App インストールの 1 手間だけ増える。

## データ保護

### 機密情報の取り扱い

- シークレット・APIキー・パスワードをリポジトリにコミットしない
- 環境変数またはシークレットマネージャーで管理する

### 個人情報

（個人情報の取り扱い方針を記載）

## 依存関係管理

（依存パッケージの更新方針・脆弱性スキャンの運用を記載）

## インシデント対応

（セキュリティインシデント発生時の対応手順を記載）
