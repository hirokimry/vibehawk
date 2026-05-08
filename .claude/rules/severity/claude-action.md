vibecorp が claude-code-action 用に保有する severity 5 段階定義（CodeRabbit からコピーした実体版）。

CodeRabbit と claude-code-action の判定軸を **完全に揃える** ため、本ファイルは `severity/coderabbit.md` の定義を実体としてコピーして保有する（外部依存を最小化し、claude-code-action 単独でも判定基準が完結する）。

## severity 5 段階（vibecorp 実体版）

| Marker | severity | 定義（重大度の意味） |
|--------|---------|------|
| 🔴 | Critical | システム障害、セキュリティ侵害、データ損失を引き起こす重大な問題 |
| 🟠 | Major | 機能・パフォーマンスに大きく影響する重要な問題 |
| 🟡 | Minor | 対応すべきだがシステムに致命的な影響はない問題 |
| 🔵 | Trivial | コード品質を高めるための軽微な提案 |
| ⚪ | Info | 情報提供のみ、対応不要 |

**注意**: 本テーブルは severity の **定義**（重大度の意味）を CodeRabbit と完全一致させて記録するもの。**修正対象とするかどうかの判定** は `.claude/rules/review-handling.md` が別途行う（vibecorp 独自運用ルール）。特に Info については、CodeRabbit デフォルトでは「対応不要」だが、vibecorp は **判定の側で**「重視軸該当なら対応」に拡張している（severity 定義そのものは変えない）。

## CodeRabbit 定義との同期

`severity/coderabbit.md`（CodeRabbit 公式仕様の記録）と本ファイルの定義は **完全に一致** させる。CodeRabbit 公式が定義を変更した場合、両方を同時に追従する。

## claude-code-action での使用

`REVIEW.md`（リポジトリ直下、claude-code-action のプロンプト）から本ファイルが Source of Truth として参照される。claude-code-action はこの severity 軸でレビュー指摘を出し、`.claude/rules/review-handling.md` の捌き基準に従って修正対象を判定する。

## 関連

- 公式定義の記録: `severity/coderabbit.md`
- 捌き基準（intent × severity）: `.claude/rules/review-handling.md`
- レビュー観点: `.claude/rules/review-observations.md`
