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

#### Anthropic への送信通知（Issue #61 で追加）

PR レビュー実行時、利用者リポジトリに配置された `.github/workflows/vibehawk-review.yml` が `claude-code-action` を呼び出し、**PR diff・PR メタデータ・コメント本文・指示プロンプトが Anthropic API に送信されます**。送信先・送信内容・利用契約は **利用者の Anthropic 契約（Claude Pro / Max OAuth）に基づきます**。vibehawk 開発者側のサーバーは関与せず、vibehawk が Anthropic との中継・代理契約を行うこともありません（GDPR / 個人情報保護法等の対応は利用者の Anthropic 契約と利用者自身の運用判断に基づく）。

利用者が責任を負う範囲:

- 社内秘・第三者著作物・個人情報を含むコードを Anthropic API に送信してよいかの判断（Anthropic ToS および利用者の社内規程に従う）
- Pro/Max OAuth Token 経由で実行されるレビューが利用者の Anthropic 利用規約に違反しないことの確認（Anthropic の利用規約改定に追従する責務）
- PR レビュー対象パスを `.vibehawk.yaml` の `path_filters` で適切に絞ることでの送信範囲制御

#### CLI 書き込み代理行為の位置づけ（Issue #61 で追加）

`npx vibehawk setup-token` のクリップボード書き込み・`npx vibehawk install --repo` の workflow PR 作成は、**利用者の明示同意（[Y/n] プロンプト）に基づく代理行為** であり、書き込み主体は利用者です（vibehawk CLI は利用者の代わりに利用者の `gh` 認証コンテキストで操作を実行します）。

- CLI が **touch しないリソース**: 利用者リポジトリの GitHub Secrets（`gh secret set` 撤去済、Issue #74）。これは利用者が GitHub Settings UI で直接登録するため、vibehawk CLI の挙動とは無関係に利用者責任の範囲となる
- CLI が **代理で touch するリソース**: OS クリップボード（明示同意後）、利用者リポジトリの workflow ファイル（`--repo` 指定時の PR 作成として）

#### claude-code-action 依存と免責の範囲（Issue #61 で再掲）

vibehawk は `anthropics/claude-code-action`（MIT ライセンス）に依存しています。同 action の挙動・バグ・課金影響について vibehawk 開発者は責任を負いません（既存 L113 免責条項と整合）。利用者は claude-code-action 自体の利用規約・更新方針も自身の責任で確認してください。

### 認証情報配布方式（Issue #72 決定、2026-05-09 / Issue #61 確定）

vibehawk CLI は利用者リポジトリの GitHub Secrets に **一切書き込まない**。利用者が以下 3 secrets を GitHub Settings UI で手動登録する全手動方針を採用する:

- `VIBEHAWK_APP_ID`（利用者本人の `vibehawk-for-<owner>` App ID）
- `VIBEHAWK_PRIVATE_KEY`（利用者本人の App の Private Key、`.pem` ファイル内容）
- `CLAUDE_CODE_OAUTH_TOKEN`（Claude Pro / Max OAuth Token、`claude setup-token` で取得）

CLI は App 作成（`npx vibehawk install`）と OAuth Token 取得補助（`npx vibehawk setup-token`）の **登録手順案内** のみを担当する。`setup-token` は明示同意の上で OS ネイティブのクリップボードに stdin 経由で token をコピーすることはできるが、`gh secret set` 等で利用者リポジトリの Secrets ストアを書き換えることは行わない。

判断根拠（メジャーサービス比較 / GitHub 公式ガイドライン / CodeRabbit 事件の教訓 / MVV 整合）は [`docs/secrets-handling.md`](secrets-handling.md) を参照。

### 免責条項（Issue #32）

vibehawk は OSS として MIT ライセンスのもと提供される。LICENSE ファイル記載の免責条項に加え、CLI 配布物（`npx vibehawk install` / `npx vibehawk setup-token`）に関して以下を明示する。

#### 免責範囲

- **スクリプト誤動作**: vibehawk CLI が想定外の挙動（API 変更追従漏れ・OS 依存バグ・依存ライブラリの脆弱性等）により利用者の GitHub 環境を意図せず変更した場合、vibehawk 開発者は一切責任を負わない
- **GitHub App 作成失敗**: GitHub Manifest API の仕様変更・利用者環境の制約により App 作成が失敗した場合、vibehawk 開発者は復旧義務を負わない
- **クリップボード経由のトークン受け渡し**: `npx vibehawk setup-token` が利用者の明示同意（`[Y/n]` プロンプト）の上で OS ネイティブのクリップボードに OAuth Token をコピーする操作について、利用者環境のクリップボード履歴 / 同居マルウェア / その他プロセスによるトークン取得リスクは利用者の運用責任とし、vibehawk 開発者は責任を負わない（CLI は stdin 経由で渡し、プロセス引数 / 環境変数には出さない設計）
- **GitHub Settings UI で利用者が登録した secrets の運用**: 利用者が GitHub Settings UI で登録した 3 secrets（`VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`）の漏洩・誤登録・上書きについて、vibehawk CLI は touch していないため vibehawk 開発者は責任を負わない
- **claude-code-action の挙動**: vibehawk が依存する `anthropics/claude-code-action`（MIT ライセンス）の挙動・バグ・課金影響について、vibehawk 開発者は責任を負わない
- **GitHub Actions の課金体系変更**: GitHub の料金プラン改定（Public 無制限終了 / Private 無料枠縮小・有料化等）により利用者に追加課金が発生した場合、vibehawk 開発者は責任を負わない（vibehawk は GitHub Actions 上で動作するが、GitHub の料金体系を制御する権限を持たない）
- **Anthropic の課金体系変更**: Anthropic の料金プラン改定（Claude Pro / Max 値上げ・廃止 / OAuth 経由実行制限等）により利用者に追加課金が発生した場合、vibehawk 開発者は責任を負わない（vibehawk は利用者の Anthropic 契約枠内で動作するが、Anthropic の料金体系を制御する権限を持たない）

#### 利用者の責務

- 本 CLI を実行する前に `--dry-run` モードで実行内容を確認すること（推奨）
- 本 CLI が表示した手順に従って GitHub Settings UI で 3 secrets を登録すること（CLI は secrets を書き込まないため、登録の正確性は利用者の責任）
- 重要な GitHub 環境（本番リポジトリ等）には予め検証用リポジトリで動作を確認してから適用すること

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

#### vibehawk 商標の登録状況（Issue #61 / CEO 判断 A 確定）

vibehawk 商標は Issue #38（商標登録申請中）で正式登録手続き中。**v0.1.0 OSS リリース時点では未登録のままリリースしている** ことを明示する:

- 登録完了までは慣習法上の商標として扱う
- 本 OSS リリース自体が vibehawk 商標の **先使用権の証拠** となるよう、リリース日時・配布物（npm package）・配布チャネル（GitHub）を記録する
- 第三者が vibehawk 商標を先取りして登録しようとした場合、本リリース日が先使用権の起点として機能する
- 登録完了後、本セクションを「登録済み（登録番号 XXXXX）」に更新する

利用者は、商標登録完了前の利用について以下のリスクを承知する:

- 第三者による商標登録 → vibehawk 開発者が異議申し立てを行う（利用者は影響を直接受けないが、長期的な命名統制の安定性に影響する可能性がある）
- 第三者による商標権侵害主張 → CLO 経路で対応（vibehawk 開発者が一次対応する）

未登録期間中の商標保護は慣習法上の権利に依拠するため、登録済み商標と比べて保護強度は限定的である。利用者はこの前提で導入判断を行うこと。

### CLI 配布物のポリシー（npm AUP 遵守、Issue #28）

`npx vibehawk install` 等の CLI 配布物は npm Acceptable Use Policy 遵守のため以下を **必須** とする:

- **MUST**: 利用者の環境（ファイルシステム / GitHub Secrets / OAuth トークン等）を変更する操作の前に、実行内容を箇条書きで表示し `[Y/n]` 明示的同意プロンプトを取得すること
- **MUST**: `--yes` / `-y` フラグで非対話実行を許容すること（CI 環境向け、利用者が事前に意思表明する経路）
- **MUST**: `--dry-run` フラグで実際の変更を行わない予行演習モードを提供すること
- **MUST**: 同意拒否時 / Ctrl+C キャンセル時に部分実行状態を残さないこと（HTTP サーバー停止・GitHub API 未呼出・ファイル未書き込みを保証）
- **MUST NOT**: 利用者の同意なしに GitHub Secrets / OAuth トークン / リポジトリ設定を変更しないこと

これは npm AUP「ユーザーに無断で破壊的変更を行うパッケージの禁止」要件への対応であり、`/cli` 配下の全コマンドに適用される。
