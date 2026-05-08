# CPO プロダクト判断記録インデックス

このファイルは目次。CPO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

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
