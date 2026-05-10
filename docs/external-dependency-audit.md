# 外部依存サービス規約整合監査・月次監視

> 本ドキュメントは vibehawk が依存する外部サービス（GitHub / Anthropic claude-code-action 等）について、(1) 利用規約・公式ガイドラインに対する規約整合性の CLO 監査結果（Issue #68）、および (2) 月次のリスク監視履歴（Issue #64）を永続化する Source of Truth である。

## 監査メタデータ

| 項目 | 値 |
|------|----|
| 直近監査日 | 2026-05-09 |
| 監査主体 | CLO レビュー（Issue #68 起票） |
| 次回見直しトリガー | 監査対象サービスの規約改定検知時、または vibehawk が新たな外部サービスへ依存を追加する時 |
| 関連ポリシー | `docs/POLICY.md`「法務・コンプライアンスポリシー」 |

## 監査対象

| 対象 | 区分 | 公式ドキュメント |
|------|------|----------------|
| GitHub Developer Terms of Service | GitHub プラットフォーム規約 | `https://docs.github.com/site-policy/github-terms/github-terms-for-additional-products-and-features` |
| GitHub Marketplace Developer Agreement | GitHub Apps 配布規約 | `https://docs.github.com/site-policy/github-terms/github-marketplace-developer-agreement` |
| GitHub Apps Manifest API（公式仕様） | App 自動作成 API | `https://docs.github.com/apps/sharing-github-apps/registering-a-github-app-from-a-manifest` |
| GitHub Apps 命名・ブランディングガイドライン | App 命名規則 | `https://docs.github.com/apps/creating-github-apps/setting-up-a-github-app/about-creating-github-apps` |
| Anthropic claude-code-action | 上流 OSS 依存（MIT） | `https://github.com/anthropics/claude-code-action` |

## 1. `vibehawk-for-<owner>` 命名の規約整合確認

### 1-1. 確認した規約条項

- **GitHub Apps 命名ガイドライン**: GitHub 公式名称・他者商標との混同を招く名称は使用してはならない
- **GitHub Marketplace 規約**: Marketplace で配布する場合、命名は GitHub・他社・他のオープンソースプロジェクトと混同を招かないこと

### 1-2. `vibehawk-for-<owner>` 命名が抵触しないことの根拠

| 観点 | 確認内容 | 結論 |
|------|----------|------|
| GitHub 公式との誤認 | 命名先頭が `vibehawk-for-` であり、`github-` / `gh-` 等の GitHub 公式接頭辞を使用していない | 抵触なし |
| 他者商標との混同 | `vibehawk` は vibe シリーズ独自命名（Issue #38 で正式商標登録手続き中、`docs/POLICY.md` L146-148 参照） | 抵触なし |
| ハイジャック・なりすまし | `<owner>` 部分は CLI 実行者本人の GitHub username で固定（`docs/POLICY.md` L131-134、`MUST` 制約） | 抵触なし |
| Marketplace 配布時の命名衝突 | 利用者ごと独立 App であり、本リポジトリ自体は Marketplace に上場しない設計（`docs/POLICY.md` Value 1）。仮に Marketplace 経由で配布する場合も `vibehawk-for-<owner>` 形式は利用者リポジトリ内で完結する | 抵触なし |
| ブランドハイジャック禁止 | `docs/POLICY.md` L133-134 で `MUST NOT` 制約として明記、命名違反時は L138-144 の取消条件で商標使用許諾を撤回可能 | 抵触なし |

### 1-3. 監査結論

`vibehawk-for-<owner>` 命名は GitHub Developer Terms of Service / GitHub Marketplace Developer Agreement / GitHub Apps 命名ガイドラインのいずれにも抵触しない。

## 2. GitHub Apps Manifest API の利用条件

### 2-1. 仕様要点

- Manifest API は GitHub 公式の正規 API であり、CLI 経由で App を一括作成することは GitHub 公式の想定利用範囲内
- Manifest を POST した結果として返る一時 `code` は **一回限り** で交換され、交換後 1 時間以内に有効期限が切れる
- Private Key は Manifest API 経由では返されず、利用者が GitHub Settings UI で個別にダウンロードする方式（vibehawk の現行実装と整合）

### 2-2. vibehawk 実装との整合確認

| 仕様要件 | vibehawk 実装 | 整合 |
|---------|-------------|------|
| ローカル一時 HTTP サーバー（callback 受信用） | `npx vibehawk install` が `127.0.0.1:8765` にローカルサーバー起動 | 整合 |
| Manifest 内容のブラウザ同意 | GitHub UI で「Create」を利用者本人が押す | 整合 |
| Private Key を CLI に保存しない | CLI は App ID と Settings URL のみ画面表示、Private Key は印字せず破棄（CISO Critical 条件） | 整合 |
| 集中ホスト型サーバーへの送信なし | localhost のみで完結、vibehawk 開発側サーバーへ通信しない（`README.md` L29） | 整合 |

### 2-3. 監査結論

GitHub Apps Manifest API の利用は公式仕様の正規利用範囲内。

## 3. claude-code-action（MIT、Anthropic 提供）の依存責務

### 3-1. 上流ライブラリの基本属性

| 項目 | 値 |
|------|----|
| ライブラリ | `anthropics/claude-code-action` |
| ライセンス | MIT |
| 提供主体 | Anthropic |
| 機能 | PR diff・コメント等を Anthropic の処理基盤に送信し、レビュー結果を返す |

### 3-2. 法的位置づけ

- vibehawk は claude-code-action を **依存ライブラリとして利用** しているのみで、Anthropic との直接契約関係には立たない（`docs/POLICY.md` Value 1「利用者の契約だけで、完結させる」）
- 利用者の workflow が claude-code-action を呼び出した時点で、利用者と Anthropic の間に Anthropic Usage Policies / Anthropic Commercial Terms of Service の契約関係が成立する（`CLAUDE_CODE_OAUTH_TOKEN` を利用者本人の Anthropic アカウントから発行）
- claude-code-action 経由で送信される PR diff・コメント・コントリビューター情報の処理は Anthropic の規約に従う

### 3-3. 免責の範囲

`docs/POLICY.md` L113 既存記述:

> **claude-code-action の挙動**: vibehawk が依存する `anthropics/claude-code-action`（MIT ライセンス）の挙動・バグ・課金影響について、vibehawk 開発者は責任を負わない

本免責は claude-code-action のバグ・脆弱性・API 仕様変更・課金挙動を含む。`docs/POLICY.md`「claude-code-action 依存の免責拡張（Issue #68）」サブセクションで補足。

### 3-4. 監査結論

claude-code-action への依存関係は MIT ライセンス上の通常利用であり、利用者と Anthropic の間で契約関係が成立する設計。vibehawk 開発者は claude-code-action の挙動責任を負わない旨を `docs/POLICY.md` L113 と Issue #68 で追加した拡張サブセクションで明示する。

## 4. 監査総括

| 観点 | 監査結果 |
|------|----------|
| `vibehawk-for-<owner>` 命名と GitHub 規約の整合 | 抵触なし |
| GitHub Apps Manifest API 利用の正当性 | 公式仕様の正規利用 |
| claude-code-action 依存の責務分界 | 利用者と Anthropic の契約関係に集約、vibehawk は無関係 |
| 利用者リポジトリの secrets 書き込み | `docs/secrets-handling.md` の通り CLI は touch しない（GitHub ToS §C.2 自動ツール責任帰属の論点が成立しない） |

監査時点で vibehawk の実装・配布物・命名規則は外部サービス規約と整合している。

## 5. 月次リスク監視（Issue #64）

外部依存サービスの規約・利用条件変更に対する月次監視結果を記録する。監視ポリシーの定義は [`docs/POLICY.md`](POLICY.md) の「外部依存リスク監視ポリシー」セクション、運用フローは [`docs/external-dependency-monitoring.md`](external-dependency-monitoring.md) を参照。

### 5-1. 監視対象

| サービス | 監視対象 | 影響度 | 一次情報源 |
|--------|--------|------|---------|
| Anthropic Claude Pro / Max | OAuth ヘッドレス利用条件、月額価格、Token 失効ポリシー | Mission 直接影響 | [Anthropic Usage Policy](https://www.anthropic.com/legal/aup) / [Anthropic Pricing](https://www.anthropic.com/pricing) |
| `anthropics/claude-code-action` | breaking change、SHA pinning 互換性 | workflow 動作影響 | [release notes](https://github.com/anthropics/claude-code-action/releases) |
| GitHub Apps Manifest API | Manifest Flow 仕様変更 | install フロー影響 | [GitHub Apps Manifest API docs](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) |
| npm Acceptable Use Policy | 同意プロンプト要件、CLI 配布規約 | 配布性影響 | [npm Acceptable Use Policies](https://docs.npmjs.com/policies/open-source-terms) |

### 5-2. 記録フォーマット

各監査エントリは以下のテーブル形式で月次に追記する:

| 項目 | 内容 |
|---|---|
| 監査日 | YYYY-MM-DD |
| 監査担当 | CEO / SM 名 |
| Anthropic Claude Pro / Max | 変更なし / 変更あり（要約 + URL） |
| `anthropics/claude-code-action` | 変更なし / 変更あり（release tag + 要約） |
| GitHub Apps Manifest API | 変更なし / 変更あり（要約 + URL） |
| npm Acceptable Use Policy | 変更なし / 変更あり（要約 + URL） |
| 検知した変更の影響度 | n/a / Mission 直接影響 / workflow 影響 / install フロー影響 / 配布性影響 |
| 起票した Issue | `#<番号>` または「不要」 |
| 次回監査予定日 | YYYY-MM-DD（原則翌月同日） |

### 5-3. 監査履歴

#### 初回監査（baseline、Issue #64 ポリシー策定時点）

| 項目 | 内容 |
|---|---|
| 監査日 | 2026-05-10 |
| 監査担当 | CEO（hirokimry） |
| Anthropic Claude Pro / Max | baseline（OAuth ヘッドレス利用継続、Pro $20 / mo、Max $100 〜 $200 / mo、Token 失効方針未告知） |
| `anthropics/claude-code-action` | baseline（SHA pin: `12310e4` / `v1`、[`docs/sha-update-history.md`](sha-update-history.md) 参照） |
| GitHub Apps Manifest API | baseline（廃止予告なし） |
| npm Acceptable Use Policy | baseline（同意プロンプト要件は [`docs/POLICY.md`](POLICY.md) の「CLI 配布物のポリシー」で遵守済み） |
| 検知した変更の影響度 | n/a |
| 起票した Issue | 不要 |
| 次回監査予定日 | 2026-06-10 |

備考: 本エントリは Issue #64 ポリシー策定時点で baseline として遡及記録したもの。今後の監査は本ファイルに月次で追記する。

#### 今後の監査

（次回監査時に追記）

## 関連

- `docs/POLICY.md`「法務・コンプライアンスポリシー」「外部依存リスク監視ポリシー」
- `docs/secrets-handling.md`（認証情報配布方式の設計判断）
- [`docs/external-dependency-monitoring.md`](external-dependency-monitoring.md): 月次監査運用フロー
- [`docs/sha-update-policy.md`](sha-update-policy.md): claude-code-action SHA 更新評価フロー
- [`docs/sha-update-history.md`](sha-update-history.md): claude-code-action SHA 更新履歴
- [`docs/cost-analysis.md`](cost-analysis.md): コスト構造（外部依存の課金影響）
- Issue #25（vibehawk-for-<owner> 命名統制）
- Issue #28（npm AUP 遵守）
- Issue #32（既存免責条項）
- Issue #33（vibehawk 商標使用許諾）
- Issue #38（vibehawk 商標登録申請）
- Issue #64（月次監視ポリシー策定）
- Issue #68（規約整合監査の起票元 CLO レビュー指摘）
- Issue #72（CLI が secret を書き込まない設計の確定）
