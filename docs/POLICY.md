# vibehawk ポリシー

> このドキュメントはプロジェクト全体のポリシーを定義する Source of Truth です。

## プロダクト方針（5 大方針）

vibehawk の責務範囲を定義する 5 原則。機能の取捨選択はすべてこの方針に従う。

### 大方針 1: カスタムは外から注入させる

専用機能として内蔵しなくても、利用者が `path_instructions` などで「こういう観点で見て」「こう振る舞って」とドキュメント・指示を Bot に注入できる仕組みは残す。**機能を内蔵せず、カスタム指示の余地だけ残せば十分**。

### 大方針 2: レビュー & 修正提案まで、コード生成は絶対にしない

責務範囲は「レビュー & 修正提案までで終わり」。docstring 自動生成・unit-test 自動生成・apply suggestions（Bot 自身による自動 commit）などのコード生成系機能は **一切実装しない**。実際にコードを直すのは利用者の責務。

ただし以下は OK:

- レビュー文脈での例示コード断片（「これをこう直す例」レベル）
- GitHub Suggestions 構文（` ```suggestion ` ブロック）の生成（利用者が 1 クリックで適用するかは利用者の意思）

NG なのは _Bot 自身が PR に commit を作る行為 / docstring 全文生成 / unit-test ファイル新設_ など、利用者の合意なくコードを増やす行為。

### 大方針 3: severity 判定はツール側、捌き方は利用者側

severity の **判定そのもの**（Critical / Major / Minor / Trivial / Info の付け方）は業界標準として **vibehawk 側** が持つ。その severity を **どう捌くか**（修正対象とするか、無視するか）は利用者の運用判断なので、**利用者側** で持つ。

### 大方針 4: 状態管理は GitHub に置く、専用 DB は持たない

永続的状態（前回レビュー時の SHA、resolve 状態、チャット文脈など）はすべて **GitHub リポジトリ自体** に置く。**内部 DB / ベクタ DB / 専用サーバーを一切持たない** ことが「LLM 課金枠以外、追加課金ゼロ」を成立させるコア設計判断。詳細は `docs/design-philosophy.md` の「状態管理ポリシー（vibehawk 固有）」を参照。

### 大方針 5: PR メタデータ操作はしない

Bot が PR に対してできることは **`inline comment` / `review summary comment` / `approve / request_changes` の発行** のみ。**PR の label 付与 / milestone 設定 / description 補完 / assignee 操作などのメタデータ操作は一切しない**。これらは利用者リポジトリの運用設定に強く依存するため、利用者側で別の GitHub Actions として実装する責務。

## 開発ポリシー

### ブランチ戦略

（ブランチ命名規則・マージ戦略を記載）

### コードレビュー

（レビューの必須条件・承認基準を記載）

### デプロイ

（デプロイフロー・承認プロセスを記載）

## コミュニケーションポリシー

（Issue・PR・ドキュメントの運用方針を記載）

## 品質ポリシー

### テスト

（テスト戦略・カバレッジ基準を記載）

### ドキュメント

（ドキュメント管理方針を記載）

## 法務・コンプライアンスポリシー

### 基本方針

vibehawk は MVV の Value に基づき、以下を法務上の根本原則とする。

- **Value 1「利用者の契約だけで、完結させる」**: vibehawk 自身は外部サービスの契約当事者にならない。LLM プロバイダー・GitHub 等の利用規約における「再販・代理利用禁止」条項の対象にならない設計を維持する。
- **Value 4「公式の道を、迂回せず歩く」**: 外部サービスの公式 API のみを使用する。スクレイピング・非公式エンドポイント・裏 API の使用は禁止する。これは GitHub / Anthropic / その他サービスの ToS 遵守を設計レベルで担保する。

### 外部サービス利用規約

- 外部サービスは公式 API のみ経由する（スクレイピング・非公式エンドポイント禁止）
- 新規外部サービス導入時は利用規約の確認を必須とする
- 利用規約の改定を検知した場合は CLO へエスカレーションする

### ライセンス方針

- 依存パッケージのライセンスはプロジェクトライセンスと互換であること
- MIT / BSD / Apache 2.0 は原則許可
- GPL 系・商用禁止ライセンスは CLO 確認必須

### データ取扱い方針

- vibehawk は利用者のコードを自サーバーに保存しない
- PR メタデータの読み取りは行うが書き換えは行わない（Value 2「観察する、書き換えない」）
- 個人情報を収集する場合は事前に CLO レビューを受ける

### 認証情報配布方式の現行方針（Issue #72 決定、2026-05-09）

CLI が利用者リポジトリの GitHub Secrets に書き込むかどうかについては、CEO 判断 (2026-05-09) により **CLI は secret を一切 touch せず、利用者が GitHub Settings UI で手動登録する方針**（案 2 採用）が確定している。判断根拠とメジャーサービス比較・GitHub 公式ガイドライン引用は [`docs/secrets-handling.md`](secrets-handling.md) を参照。

本ドキュメント内の `setup-token` および `gh secret set` に関する記述（後述の免責条項を含む）は、本方針確定 **以前** の Issue #26 実装を前提として書かれた **旧方針記述** であり、本ファイル全面改訂を担当する **Issue #61 マージ完了まで暫定的に残置** している。Issue #61 完了時に旧方針記述は撤去される。

実装側の撤去は Issue #74（`cli/oauth.js` の `gh secret set` 撤去）で別途進行する。

### 免責条項（Issue #32、※ 旧方針時点で記述。Issue #61 で更新予定）

> ⚠️ **旧方針 (Issue #61 まで)**: 本セクションは Issue #26 の `setup-token` 自動登録経路を前提として書かれている。現行方針（CLI は secret を touch しない）への整合は Issue #61 の docs 全面改訂で行う。判断根拠は [`docs/secrets-handling.md`](secrets-handling.md) を参照。

vibehawk は OSS として MIT ライセンスのもと提供される。LICENSE ファイル記載の免責条項に加え、CLI 配布物（`npx vibehawk install` / `npx vibehawk setup-token`）に関して以下を明示する。

#### 免責範囲

- **スクリプト誤動作**: vibehawk CLI が想定外の挙動（API 変更追従漏れ・OS 依存バグ・依存ライブラリの脆弱性等）により利用者の GitHub 環境を意図せず変更した場合、vibehawk 開発者は一切責任を負わない
- **secrets 上書き（旧方針 Issue #61 まで）**: `npx vibehawk setup-token` が利用者の同意（`[Y/n]` プロンプト）の上で既存 `CLAUDE_CODE_OAUTH_TOKEN` を上書きしていた挙動について。Issue #74 完了後は CLI が secret を書き込まないためこの免責項目は実質適用対象が消滅する。Issue #61 の docs 改訂で記述を更新する
- **GitHub App 作成失敗**: GitHub Manifest API の仕様変更・利用者環境の制約により App 作成が失敗した場合、vibehawk 開発者は復旧義務を負わない
- **claude-code-action の挙動**: vibehawk が依存する `anthropics/claude-code-action`（MIT ライセンス）の挙動・バグ・課金影響について、vibehawk 開発者は責任を負わない

#### 利用者の責務

- 本 CLI を実行する前に `--dry-run` モードで実行内容を確認すること（推奨）
- 本 CLI が変更した GitHub Secrets / App / workflow ファイルの内容を利用者自身で確認・運用すること（※ Issue #74 完了後の現行方針では、CLI は GitHub Secrets を変更しない）
- 重要な GitHub 環境（本番リポジトリ等）には予め検証用リポジトリで CLI 動作を確認してから適用すること

vibehawk は MVV の Value 1「利用者の契約だけで、完結させる」に従い、vibehawk 開発側のサーバー・課金・データ保存を一切持たない設計のため、利用者環境での動作はすべて GitHub の規約と利用者の運用責任の範囲内で完結する。

### vibehawk-for-<owner> 命名の商標使用許諾（Issue #33）

`npx vibehawk install` で作成される GitHub App の名前は `vibehawk-for-<owner>` 形式に固定される（命名統制、Issue #25）。本命名規則の商標使用について以下を明示する。

#### 許諾範囲

vibehawk 開発者（GitHub: hirokimry）は、`vibehawk-for-<owner>` 形式の名前で作成される利用者の GitHub App に関して、`vibehawk` 商標の使用を以下の条件で許諾する:

- **MUST**: `npx vibehawk install` CLI 経由で作成された App であること
- **MUST**: 命名は `vibehawk-for-<owner>` 形式に厳密に従うこと（先頭の `vibehawk-for-` プレフィックスを変更しない）
- **MUST NOT**: vibehawk と無関係な目的（ブランドハイジャック・なりすまし・ブランド毀損行為）に App 名を使用しないこと
- **MUST NOT**: vibehawk 開発者の事前許可なく `vibehawk-` プレフィックスの他の App 名（`vibehawk-pro`、`vibehawk-enterprise` 等）を作成しないこと

#### 取消条件

以下の場合、vibehawk 開発者は商標使用許諾を一方的に取り消す権利を保有する:

- 利用者が許諾範囲（上記 MUST/MUST NOT）に違反した場合
- vibehawk 商標の保護のため必要と vibehawk 開発者が判断した場合
- 第三者の権利を侵害する利用が判明した場合

取消の場合、利用者は速やかに対象 App を削除または改名する義務を負う。

#### vibehawk 商標の登録状況

vibehawk 商標は Issue #38（商標登録申請）で正式登録手続き中。登録完了までは事実上の慣習法上の商標として扱う。

### CLI 配布物のポリシー（npm AUP 遵守、Issue #28）

`npx vibehawk install` 等の CLI 配布物は npm Acceptable Use Policy 遵守のため以下を **必須** とする:

- **MUST**: 利用者の環境（ファイルシステム / GitHub Secrets / OAuth トークン等）を変更する操作の前に、実行内容を箇条書きで表示し `[Y/n]` 明示的同意プロンプトを取得すること
- **MUST**: `--yes` / `-y` フラグで非対話実行を許容すること（CI 環境向け、利用者が事前に意思表明する経路）
- **MUST**: `--dry-run` フラグで実際の変更を行わない予行演習モードを提供すること
- **MUST**: 同意拒否時 / Ctrl+C キャンセル時に部分実行状態を残さないこと（HTTP サーバー停止・GitHub API 未呼出・ファイル未書き込みを保証）
- **MUST NOT**: 利用者の同意なしに GitHub Secrets / OAuth トークン / リポジトリ設定を変更しないこと

これは npm AUP「ユーザーに無断で破壊的変更を行うパッケージの禁止」要件への対応であり、`/cli` 配下の全コマンドに適用される。
