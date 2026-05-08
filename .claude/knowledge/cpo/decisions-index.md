# CPO プロダクト判断記録インデックス

このファイルは目次。CPO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

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
