# CPO プロダクト判断記録インデックス

このファイルは目次。CPO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

- 2026-06-13 — Issue #346 / PR #348 配布 workflow 自己完結化 — dogfooding（テンプレ完全一致）は外部破綻を構造的に隠すと確定。「自リポジトリで動く ≠ 外部で動く」を配布系変更の必須レビュー観点化。docs 記載コマンドは実在検証必須（`setup --overwrite` は存在せず `install --repo <o/r> --overwrite` が正）。v0.2.3 が外部成立の節目
- 2026-06-12 — Issue #344 README 再編完了（PR #345） — vibehawk README は 9 見出し構成（ヒーロー→クイックスタート→何ができる？→何がユニークか→安全と課金→機能一覧→詳細ドキュメント→設計思想→ライセンス）を正式構成として確定。保全対象フレーズ 7 項目の grep 検証運用を確立
- 2026-06-12 — Issue #344 README 再編計画 平社員指摘メタレビュー — 計画続行可。指摘 5/6 件採用（タスク 10 保全検証新設・blockquote 再配置先明示が必須）、指摘 1 件除外（タスク 6 既存テストでカバー済み）
- 2026-06-12 — README 構成再編 Issue（vibecorp 流 30 秒スキャン） — OK: Mission 伝達効率向上・シンプルさ原則に合致。documentation.md の英語化ルール乖離は継続するが本 Issue スコープは妥当
- 2026-05-30 — Issue #230 インライン指摘フォーマット — CodeRabbit 完全模倣（方針 A）に確定。枠は模倣・中身は日本語/vibehawk 化、コールアウトは実測ほぼ 0% で非模倣。実測 157 件根拠。実装は #251/#263 で main マージ済み
- 2026-05-24 — Issue #222 APPROVE 時 review body 空化 — APPROVE 時に body="" + comments=[] とする仕様変更を承認。CodeRabbit 実測 9/9 件一致・タイムラインノイズ除去・sticky walkthrough で情報損失なし
- 2026-05-08 — ship #6 specification.md アーキテクチャ章 bash サンプル — spec 内サンプルは「参照的・非規範的」と明示する方針。How（実装詳細）の混在は分離推奨
- 2026-05-08 — ship #6 README 乖離 3 PR 連続放置 — 認知パターンとして記録。5 PR 連続でエスカレーション検討。起票判断は CEO 管轄
- 2026-05-08 — ship #6 C*O 間判断割れ（ai-organization.md 配置） — CPO 推奨（B 案: 移動）が CTO 判定（A 案: CEO 意図尊重）で覆されるパターンを確認
- 2026-05-08 — MVV 確定（CEO ⇄ CPO 合議・6 ラウンド推敲） — 状態描写型 Mission/Vision・2 部構造 Values に確定。技術原則は design-philosophy.md に分離
- 2026-05-08 — Vision 案 A-1 表現推敲 — 「一度払った AI が」→「一度の支払いで AI が」を最終推奨（Mission の二重支払い否定を保持しつつ擬人化・物化を回避）

## 運用ルール

### エントリ書式

1 エントリ = 1 行:

```text
- YYYY-MM-DD — Issue #NNN または トピック名 — 結論の一行要約
```

### 四半期の命名

- 01-03 → Q1、04-06 → Q2、07-09 → Q3、10-12 → Q4
- 例: 2026-04-18 → `decisions/2026-Q2.md`

### 追記手順

1. `decisions/YYYY-QN.md` に詳細を追記（ファイルがなければ新規作成、`decisions/` ディレクトリ自動作成）
2. 本ファイルのエントリセクションに 1 行サマリを追記（新しい順で上に追加）

詳細仕様: `docs/migration-decisions-index.md`
