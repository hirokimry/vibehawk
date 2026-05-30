# vibehawk AI 組織運用

> [!IMPORTANT]
> このドキュメントは AI エージェントによる組織運用の方針を定義する Source of Truth。

## 基本思想

AI エージェントチームがプロダクト開発のあらゆる側面を担い、人間はオーナーとして意思決定に集中する。

- AI エージェントチームがプロダクト開発のあらゆる側面を担う
- 各エージェントは専門領域を持ち、フラットな関係で協働する
- 全ての判断は `MVV.md` に基づく
- エージェント間に上下関係はなく、提案と調整で連携する
- 管轄外のファイルは role-gate フックにより自動的にブロックされる

## 組織構成

各エージェントは明確な管轄を持ち、管轄外のファイルは編集しない。

| ロール | 役割 | docs/ 編集権限 |
|--------|------|---------------|
| COO（番頭） | 全体統括・進捗把握・エージェント間調整 | なし（調整役のため直接編集しない） |
| CTO | コード品質・アーキテクチャ・技術的負債の番人 | `docs/specification.md`（技術スタック部分）, `docs/design-philosophy.md` |
| CPO | プロダクト方針・仕様の番人 | `docs/specification.md`, `docs/screen-flow.md` |
| CFO | コスト分析・予算管理の統括 | なし（経理分析員に委任） |
| CLO | 法務・コンプライアンスの統括 | なし（法務分析員に委任） |
| CISO | セキュリティの統括 | なし（セキュリティ分析員に委任） |

**原則: 仕様は CPO、設計は CTO** — プロダクト仕様（ユーザー視点・機能・プリセット）は `docs/specification.md` で CPO が管轄し、技術設計（アーキテクチャ・フック・スキル・sandbox 等）は `docs/design-philosophy.md` で CTO が管轄する。

### チーム構成

C-Level エージェントの下に専門分析員を配置し、詳細な分析・調査を委任する。

| チーム | C-Level | 分析員 | 分析員の役割 | docs/ 編集権限 |
|--------|---------|--------|-------------|---------------|
| 法務チーム | CLO | 法務分析員（legal） | ライセンス分析・コンプライアンスチェック | `docs/POLICY.md` |
| 経理チーム | CFO | 経理分析員（accounting） | API コスト計算・予算消化率の算出 | `docs/cost-analysis.md` |
| セキュリティチーム | CISO | セキュリティ分析員（security） | 脆弱性スキャン・セキュリティポリシー検証 | `docs/SECURITY.md` |

分析員は C-Level エージェントから呼び出され、結果を報告する。
分析員が各管轄の docs/ ファイルを直接編集する権限を持つ（role-gate フックで制御）。

## 権限モデル

### 管轄ファイルの更新権限

- 各エージェントは自身の管轄ファイルのみ編集可能
- 管轄外のファイルを編集する場合は、管轄エージェントの承認が必要
- `knowledge/` 配下（`.claude/knowledge/` を含む）は全ロールが編集可能（ナレッジ蓄積のため）

### 承認フロー

管轄外のファイル更新が必要な場合、以下のプロセスで承認を得る。

1. **更新要求**: 変更を必要とするエージェントが、変更内容と理由を明示する
2. **管轄エージェントの確認**: 管轄エージェントが変更内容を確認し、MVV との整合性を検証する
3. **承認または却下**: 管轄エージェントが変更を承認するか、修正を求める
4. **実行**: 承認された場合、管轄エージェントが自身の手で変更を実施する

> [!NOTE]
> role-gate フックが有効な場合、管轄外のファイル編集は技術的にもブロックされる。
> 承認フローは管轄エージェント自身が変更を代行する形で運用する。

### MVV 編集権限

- ✅ MUST: `MVV.md` の編集はファウンダーのみが行う
- ❌ MUST NOT: エージェントが MVV の改変・改変提案を行わないこと

## 段階的導入計画

チームの成熟度に応じて段階的にエージェントを追加する。各フェーズは vibecorp のプリセット（minimal / standard / full）に対応する。

| Phase | 内容 | エージェント構成 | 対応プリセット |
|-------|------|----------------|---------------|
| Phase 0 | 準備 | なし（手動運用） | minimal |
| Phase 1 | レビュー体制 | CTO + CPO | standard |
| Phase 2 | コスト・法務 | + CFO + CLO + 分析員 | full |
| Phase 3 | セキュリティ | + CISO + 分析員 | full |
| Phase 4 | フル組織 | + COO（全エージェント稼働） | full |

### 各フェーズの詳細

#### Phase 0: 準備（minimal プリセット）

- vibecorp をインストールし、基本的なスキルとフックを導入する
- MVV.md を策定する
- エージェントなしで手動運用しながら、開発フローに慣れる
- protect-files フックでファイル保護を開始する
- /vibecorp:review, /vibecorp:commit, /vibecorp:pr 等の基本スキルを活用する

#### Phase 1: レビュー体制（standard プリセット）

- CTO + CPO エージェントを有効化し、コード品質とプロダクト方針のレビューを開始する
- /vibecorp:sync-check, /vibecorp:review-to-rules でドキュメントとコードの整合性を維持する
- sync-gate, review-to-rules-gate フックでゲート制御を導入する

#### Phase 2: コスト・法務（full プリセット）

- CFO + 経理分析員を追加し、API コストの可視化・予算管理を開始する
- CLO + 法務分析員を追加し、ライセンス・コンプライアンスチェックを開始する
- role-gate フックで管轄外編集のブロックを開始する

#### Phase 3: セキュリティ（full プリセット）

- CISO + セキュリティ分析員を追加し、セキュリティ監査体制を確立する
- /vibecorp:diagnose スキルで自律的な問題検出を開始する

#### Phase 4: フル組織（full プリセット）

- COO を追加し、全エージェントの連携・進捗管理を統括する
- 全 C-suite + 分析員が稼働し、AI 組織としてフル稼働する
- /vibecorp:ship-parallel で複数 Issue の並列処理が可能になる

## プロダクト実行モデル（GitHub Actions 同期実行）

> [!NOTE]
> 本セクションは vibehawk **プロダクト自体の実行設計** であり、AI 組織運用とは性質が異なる。
> Issue #6 完了条件に従って本ファイルに配置するが、将来的に `docs/design-philosophy.md` への移動を検討する余地がある。

vibehawk のプロダクト本体（PR レビュー実行基盤）は、GitHub Actions の workflow が PR イベントを受けて、その中で同期的に LLM を呼び、コメントを投稿して終了する。
専用キューや別 runner は持たない。

### 実行フロー

```text
PR が立つ
  ↓
GitHub Actions workflow が起動（pull_request イベント）
  ↓
ジョブ内で claude-code-action を直接呼ぶ
  ↓
LLM 呼び出し → レビュー結果生成
  ↓
gh api でコメント投稿・edit・resolve
  ↓
ジョブ終了
```

### 並列実行制御

利用者の workflow ファイルで `concurrency:` を宣言する。
新しい push が来たら古いレビューを中止する設計が推奨。

```yaml
concurrency:
  group: vibehawk-${{ github.event.pull_request.number }}
  cancel-in-progress: true
```

### 採用理由

| 観点 | 内容 |
|---|---|
| 5 大方針 4「DB 持たない」 | 専用キューサーバーを持たないことで完全整合 |
| 「LLM 課金枠以外、追加課金ゼロ」 | GitHub Actions 標準機能だけで完結、追加インフラ費用ゼロ |
| ジョブタイムアウト | 6 時間（GitHub Actions 標準）→ LLM レビューには十分 |
| 業界標準 | claude-code-action / GitHub Super Linter / 多くの review bot OSS が同じ構造 |

## 🔗 関連

| ドキュメント | 内容 |
|---|---|
| [`MVV.md`](../MVV.md) | プロダクトの根幹方針（全判断の基準） |
| [`docs/specification.md`](specification.md) | 機能仕様（CPO 管轄） |
| [`docs/design-philosophy.md`](design-philosophy.md) | 技術設計の根拠（CTO 管轄） |
| [`docs/SECURITY.md`](SECURITY.md) | セキュリティ設計（CISO 管轄） |
| [`docs/POLICY.md`](POLICY.md) | 法務・コンプライアンス（CLO / 法務分析員 管轄） |
| [`docs/cost-analysis.md`](cost-analysis.md) | コスト設計（CFO / 経理分析員 管轄） |
