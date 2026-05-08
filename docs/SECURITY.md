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
- `administration: write` / `secrets: write` / `workflows: write` / `id-token: write` は付与しない（Issue #22 修正後、`id-token: write` も禁止権限に追加）

### 認証経路の設計（OSS 配布版、Issue #22 修正後）

vibehawk の認証経路は **`CLAUDE_CODE_OAUTH_TOKEN` 1 系統** に統合されている。CEO の GitHub App Private Key を利用者に配布する設計は OSS 配布不可能であるため Issue #22 で撤廃した。

```text
利用者リポジトリの GitHub Actions
   └─ ① Anthropic 認証（LLM 呼び出し）
         └─ CLAUDE_CODE_OAUTH_TOKEN（利用者の Claude Pro / Max 枠）

   GitHub コメント投稿は GitHub Actions 自動発行の
   secrets.GITHUB_TOKEN（job permissions に scope 限定、短寿命）を使用
```

| 系統 | トークン | 特性 |
|---|---|---|
| LLM 認証 | `CLAUDE_CODE_OAUTH_TOKEN` | 利用者が GitHub Secrets に設定。利用者の Anthropic 契約に紐づく |
| GitHub 認証 | `secrets.GITHUB_TOKEN` | GitHub Actions が自動発行。job 終了時に失効する短寿命トークン。利用者設定不要 |

claude-code-action 公式 docs が `secrets.GITHUB_TOKEN` を推奨設定として明記している（auto-scope / 短寿命 / prompt injection 耐性）ため、本設計はベストプラクティスに準拠する。

#### 利用者準備手順（1 secret のみ）

| 手順 | 内容 |
|---|---|
| 1 | リポジトリに `.github/workflows/vibehawk-review.yml` を配置（テンプレートからコピペ） |
| 2 | Settings → Secrets and variables → Actions で `CLAUDE_CODE_OAUTH_TOKEN` を設定 |
| 3 | PR を作成すると `github-actions[bot]` 名義でレビューサマリが投稿される |

#### 投稿者表示の妥協

- 投稿者は `github-actions[bot]` 名義になる（`vibehawk[bot]` 名義ではない）
- これは Value 1「利用者の契約だけで、完結させる」を優先した結論
- ブランド表示は妥協されたが、利用者は GitHub App インストール不要・Private Key 配布不要・1 secret 設定のみで導入できる利点を得る

#### Fork PR の扱い

- Fork PR からの起動時、`secrets.GITHUB_TOKEN` は read 限定権限となるため `gh pr comment` が失敗する可能性が高い
- vibehawk は本シナリオを **対象外** として扱う（`pull_request_target` は `.claude/rules/autonomous-restrictions.md` §6 不可領域のため使用しない）
- 同一リポジトリ内の通常 PR では正常に動作する

#### v2 拡張余地（将来検討）

GitHub App 経路を将来再導入する場合の条件:

- 利用者自身が GitHub App を発行・設定するルート（vibehawk 開発側の Private Key を配布しない）
- Anthropic 公式 `claude` App と同等の仕組み調査
- v2 で再導入する場合も Issue #22 で確立した「1 secret のみ」の利用者体験を後退させない設計を最優先とする

### Claude OAuth Token の取得・登録（Issue #26）

`npx vibehawk setup-token` は利用者の `CLAUDE_CODE_OAUTH_TOKEN` を対象リポジトリの GitHub Secrets に登録する。

#### 設計判断

- vibehawk は Anthropic OAuth client_id を保有しない（Value 4「公式の道を、迂回せず歩く」）
- 公式 `claude setup-token` フロー（Anthropic 公式の Claude Code CLI が提供）に委譲
- 利用者は別ターミナルで `claude setup-token` を実行してトークンを取得し、vibehawk CLI のプロンプトに貼り付ける
- vibehawk は受け取ったトークンを `gh secret set` で対象リポジトリに登録するのみ

#### 読み書き範囲

| リソース | 操作 | 経路 |
|---|---|---|
| 利用者の OAuth Token | 受領（メモリ上のみ） | CLI プロンプト経由（標準入力） |
| GitHub Secrets | 書き込み（CLAUDE_CODE_OAUTH_TOKEN のみ） | `gh secret set` 経由（公式 GitHub CLI） |
| ローカルファイル | **書き込み禁止** | （該当なし） |
| vibehawk 運営側サーバー | **通信禁止** | （該当なし） |

#### 既存 secret 上書き時の挙動

- 既に `CLAUDE_CODE_OAUTH_TOKEN` が登録済みの場合、CLI が `[y/N]` プロンプトで上書き確認する
- N（デフォルト）の場合、既存値を保持して setup を中断する
- Y の場合のみ `gh secret set` で上書きする

#### キャンセル時の挙動

- OAuth フローを途中で中断した場合（Ctrl+C 等）、トークンを GitHub Secrets に書き込まない
- ローカル状態は変更されない（部分セットアップ状態を残さない）

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

## npm 配布のセキュリティ（Issue #30）

vibehawk CLI は npm registry 経由で配布される。npm 侵害は世界中の利用者に偽物 vibehawk が配布される最大のサプライチェーン攻撃面のため、以下の **CISO Critical 条件** を遵守する。

### CISO Critical 条件 3 点

| 要件 | 実装 |
|---|---|
| npm publish アカウントの 2FA 必須 | npmjs.com Settings 側で設定（CEO 手動）、authenticator app + recovery code |
| GitHub Actions OIDC 経由の publish のみ許可 | `.github/workflows/release.yml`、`permissions: id-token: write` で短寿命 token を発行 |
| npm provenance 署名 | `npm publish --provenance --access public` で改ざん検知。`package.json` の `publishConfig.provenance: true` で常時有効 |

### 手動 publish 禁止

- 開発者個人の npm token を使った `npm publish` は **運用上禁止** する
- リリースは GitHub Releases 作成 → `.github/workflows/release.yml` 自動起動の経路のみ
- 詳細は `CONTRIBUTING.md` の「リリースプロセス」を参照

### npm 侵害時のインシデント対応（Issue #34 で詳細化予定）

万が一 vibehawk の npm パッケージが改ざんされた場合:

1. 改ざんを検知次第、npm Support に通報して該当 version を unpublish 申請
2. GitHub Releases に該当 version の警告を追記
3. 利用者向けにセキュリティアドバイザリ（GitHub Security Advisory）を発行
4. 改ざん経路を特定し、再発防止策を CISO レビュー後に実装

## インシデント対応

（セキュリティインシデント発生時の対応手順を記載）
