# セキュリティ判断原則

docs/SECURITY.md のセキュリティポリシーと MVV.md から導出される、セキュリティ分析員の判断基準。
セキュリティポリシーの詳細は `docs/SECURITY.md` を参照すること。

## 脅威モデル

vibehawk 固有の脅威モデル。「専用 DB 非保有・状態は GitHub に置く」設計（`docs/design-philosophy.md` 状態管理ポリシー）と「公式経路限定」（Value 4）を前提とする。

### 想定する攻撃者

| 攻撃者 | 動機 | 攻撃目的 |
|--------|------|---------|
| 悪意ある PR 投稿者 | 承認プロセスの迂回 | レビューなしでコードをマージさせる |
| Fork PR 経由の外部攻撃者 | secrets 窃取 | GitHub Actions の secrets を OIDC 以外の手段で漏洩させる |
| サプライチェーン攻撃者 | 依存パッケージへの侵入 | vibehawk が依存するパッケージへのマルウェア混入 |
| 内部権限昇格 | ガードレール迂回 | diagnose-guard 等のセキュリティフックを無効化する |

### 攻撃面

vibehawk の攻撃面は「公式経路限定・自前ストレージ非保有」設計によって意図的に小さく保たれている。

**残存する攻撃面:**

- **GitHub API 呼び出し経路**: `gh` コマンド・GitHub Actions で使う token のスコープ設定ミス
- **AI エージェントへのプロンプトインジェクション**: PR 本文・コメント経由で AI エージェントに意図しない操作をさせる
- **ゲートスタンプの偽造**: `~/.cache/vibecorp/state/` 配下のスタンプファイルを同一ユーザープロセスから偽造してゲートを突破する（`docs/design-philosophy.md` 脅威モデルセクション参照）
- **依存パッケージの既知 CVE**: `gh`、`jq`、`bash` 等のバージョンに起因する脆弱性
- **GitHub Actions ワークフローの設定ミス**: `pull_request_target` + secrets 参照による Fork PR からの secrets 漏洩
- **`CLAUDE_CODE_OAUTH_TOKEN` の secrets 漏洩**: GitHub Actions secrets が Fork PR 経由で外部に露出した場合、利用者の Claude Max 枠が不正使用される。`autonomous-restrictions.md` §6 の Fork PR 除外条件削除が主要な攻撃経路
- **Installation Token の権限昇格**: `vibehawk[bot]` の GitHub App Installation Token は `pull_requests:write` / `issues:write` を保有する。Token が漏洩した場合、攻撃者が任意の PR に approve/request_changes を送れる。Token の有効期限（GitHub 規定: 1 時間）と最小権限設計（`administration:write` 等の禁止権限を含まない）が主要な防衛線

**設計により排除された攻撃面:**

- vibehawk サーバー側 DB への直接攻撃（DB が存在しないため攻撃不可）
- vibehawk 管理の認証情報への不正アクセス（認証情報を保持しないため）
- セッション固定攻撃（独自セッション管理を行わないため）

## 保護すべき資産

vibehawk は自前ストレージを持たないため、保護すべき資産の多くは GitHub 側に存在する。vibehawk が一時的に扱う情報のみを管理対象とする。

| 資産 | 機密度 | 保護方針 |
|------|--------|---------|
| GitHub アクセストークン（`CLAUDE_CODE_OAUTH_TOKEN` 等） | 最高 | GitHub Actions Secrets 経由のみ注入。ログ出力・リポジトリへの書き込み禁止 |
| `ANTHROPIC_API_KEY` | 最高 | GitHub Actions Secrets 経由のみ注入。スクリプト・設定ファイルへのハードコーディング禁止 |
| PR 本文・コードレビューコメント（利用者リポジトリの情報） | 高 | 実行時の揮発情報として扱う。vibehawk 側に永続化しない |
| ゲートスタンプファイル（`~/.cache/vibecorp/state/`） | 中 | `chmod 700` で他ユーザーからの偽造を防止。同一ユーザープロセスからの偽造は信頼境界外（スコープ外）|
| vibehawk のガードレール設定（hooks / settings.json） | 中 | `protect-files.sh` で保護。`autonomous-restrictions.md` の不可領域として定義 |

**設計上から存在しない資産（保護対象外）:**

- 利用者のパスワード・認証情報（vibehawk は保持しない）
- 利用者のコード・データのバックアップ（GitHub のオリジナルが正として存在する）
- vibehawk 独自の DB / セッションストレージ（設計上非保有）

## approve/request_changes の設計意図（ship #6 確定）

`pull_requests:write` 権限は技術的に `approve` / `request_changes` の実行を可能にするが、vibehawk はこれを**使用しない**という設計意図を明示する。

### 根拠

| 観点 | 内容 |
|------|------|
| Value 2「観察する、書き換えない」| PR メタデータ（レビューステータス）を変更することは「書き換え」に該当する |
| Value 3「指摘する、強制しない」| approve/request_changes はマージ可否を強制する行為であり、「強制しない」に反する |
| 権限設計の一貫性 | 最小権限の原則として `pull_requests:write` の用途を inline comment / サマリ投稿 / edit / resolve に限定する |

### 判断

- `pull_requests:write` スコープ内で approve/request_changes を**呼び出すコードを実装しない**
- 将来実装を検討する場合は MVV の Value 2/3 との整合性を CISO が再評価する
- SECURITY.md の App 権限表には `pull_requests:write` の用途として approve/request_changes を**列挙済み**だが、これは技術的に可能な操作の列挙であり、「使用する」の宣言ではない

### エスカレーション条件

approve/request_changes を実装しようとする PR が提出された場合、CISO は Value 2/3 違反の可能性として**必ずエスカレーション**する。

## OWASP Top 10 対応方針

<!-- プロジェクトに関連する項目を重点的に記述する -->

1. **インジェクション**: ユーザー入力は必ずサニタイズ・パラメタライズする
2. **認証の不備**: セッション管理は SECURITY.md の方針に従う
3. **機密データの露出**: シークレットをコードに含めない。ログに機密情報を出力しない
4. **アクセス制御の不備**: 最小権限の原則を適用する
5. **セキュリティの設定ミス**: デフォルト設定を本番で使わない

## レビュー時の判断基準

### 即ブロック

<!-- 問答無用で差し戻すべきセキュリティリスクを記述する -->

- シークレット・API キー・パスワードのハードコーディング
- SQL インジェクション・コマンドインジェクションの可能性がある入力処理
- 認証・認可チェックのバイパスまたは無効化
- 暗号化されていない機密データの送信・保存

### 要対応（CISO へエスカレーション）

<!-- CISO の判断が必要なケースを記述する -->

- 新しい認証・認可フローの導入
- 暗号化方式・ハッシュアルゴリズムの変更
- セキュリティヘッダー・CORS 設定の変更
- 依存パッケージの既知の脆弱性（CVE）

### 許容

<!-- 追加確認なしで承認できるケースを記述する -->

- セキュリティ強化の変更（入力バリデーション追加、ヘッダー強化等）
- セキュリティに影響しないコード変更
- 既知の脆弱性がない依存パッケージの更新

## エスカレーション基準

以下の場合は必ず CISO にエスカレーションする:

- 脆弱性を1件でも検出した場合
- 合議で意見が割れた場合
- SECURITY.md に記載のないセキュリティパターンに遭遇した場合
- 攻撃チェーンの可能性がある場合（単体では軽微でも組み合わせで危険）
