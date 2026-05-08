# vibehawk セキュリティポリシー

> このドキュメントはプロジェクトのセキュリティ方針を定義する Source of Truth です。

## セキュリティ方針

vibehawk は MVV（特に Value 1・Value 4）を設計の起点とするセキュリティ方針を採用する。

### Value 4 に基づく公式経路限定原則

「公式の道を、迂回せず歩く」— 裏 API・スクレイピングを選ばず、公式に案内された経路だけで構築する。

この Value はセキュリティ方針と直接接続している:

- **認証は GitHub の公式 OAuth フローのみ使用する。** 非公式トークン取得・セッションハイジャック等の手段を選ばない
- **GitHub API は公式エンドポイント経由のみ使用する。** 非公式 GraphQL エンドポイント・レートリミット回避目的のスクレイピング等は禁止
- 公式 API の仕様外の挙動に依存したコードはセキュリティ上の問題と同等に扱い、差し戻しの対象とする

### Value 1 に基づく自前ストレージ非保有原則

「利用者の契約だけで、完結させる」— 専用 DB を持たず、状態は GitHub に置く（`docs/design-philosophy.md` 状態管理ポリシー参照）。

これはセキュリティ構造上の以下のリスクを根本的に排除する:

- **情報漏洩リスクの排除**: vibehawk 自身が機密データを蓄積・保管しないため、vibehawk サーバー側からの情報漏洩の攻撃面がない
- **認証情報管理リスクの排除**: 利用者の GitHub トークン等を vibehawk 側で保持しない。アクセス制御の責務は GitHub に完全委譲される
- **データ侵害スコープの限定**: 仮に vibehawk の実行環境が侵害されても、攻撃者が入手できるのは実行時の揮発情報のみ（永続ストレージがないため）

### 責務委譲によるアクセス制御

状態を GitHub に置く設計により、利用者のリポジトリ・組織に設定された GitHub のアクセス制御（Branch Protection / CODEOWNERS / Organization ポリシー等）がそのまま vibehawk の操作にも適用される。vibehawk が独自のアクセス制御レイヤーを持つ必要がない。

## 脆弱性報告

（脆弱性を発見した場合の報告フロー・連絡先を記載）

## 認証・認可

### 認証方式

vibehawk は GitHub の公式 OAuth アプリケーション認証のみを使用する（Value 4「公式の道を、迂回せず歩く」）。

- GitHub OAuth App または GitHub App（GitHub Actions OIDC）経由でのみ認証を行う
- 非公式な手段（クッキー流用・セッショントークン抽出等）によるアクセスは禁止
- `claude-code-action` が利用する `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` は GitHub Actions の Secrets 経由で注入する（リポジトリへの直書き・ログ出力禁止）

### 認可モデル

vibehawk 独自の認可レイヤーは持たない。GitHub のリポジトリ権限・Organization 権限に完全委譲する。

- vibehawk が実行できる操作は、実行時の GitHub トークンに紐づく権限スコープに限定される
- 権限の昇格・スコープ外アクセスを試みるコードはセキュリティ違反として即ブロック対象

### CI エージェントの権限管理

GitHub Actions 上で動作する claude-code-action には最小限の権限のみ付与する（`.claude/rules/autonomous-restrictions.md` 参照）。Fork PR からの secrets 漏洩を防ぐため以下を遵守する:

- Fork PR で `pull_request_target` トリガーを使用しない
- `administration: write` / `secrets: write` / `workflows: write` は付与しない
- `id-token: write` は GitHub OIDC 認証のみを目的とし CISO 承認済みの例外として許可

## データ保護

### 機密情報の取り扱い

- シークレット・APIキー・パスワードをリポジトリにコミットしない
- 環境変数またはシークレットマネージャーで管理する

### 個人情報

vibehawk は専用 DB を持たない設計（`docs/design-philosophy.md` 状態管理ポリシー）により、個人情報を自前のストレージに蓄積しない。振る舞いとして観察した PR メタデータ・コメント等は GitHub リポジトリ上に存在するものであり、vibehawk がそれらを外部に転送・保存することはない。

例外なく以下を遵守する:

- 利用者の GitHub アクセストークン・メールアドレス・個人識別情報を vibehawk の実行ログ外に書き出さない
- API レスポンスに含まれる個人情報をキャッシュ・永続化しない（キャッシュ層非保有の原則）

## 依存関係管理

（依存パッケージの更新方針・脆弱性スキャンの運用を記載）

## インシデント対応

（セキュリティインシデント発生時の対応手順を記載）
