# CTO 技術判断記録インデックス

このファイルは目次。CTO エージェントが step 1 で毎回 Read する。
関連する過去判断を特定したら `decisions/YYYY-QN.md` を追加で Read する。

## エントリ

- 2026-05-08 — PR #12: vibehawk MVV 制定 — `grep -F ... > /dev/null` で終了コード回避・状態管理はGitHubリソースのみ・固有セクションはvibecorp由来より前に配置

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
