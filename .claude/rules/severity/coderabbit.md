CodeRabbit 公式 severity 5 段階定義の記録（**外部仕様、変更不可**）。

vibecorp は CodeRabbit と並走運用するため、CodeRabbit が出力する severity を理解する必要がある。本ドキュメントは [CodeRabbit 公式 docs](https://docs.coderabbit.ai/guides/code-review-overview) からの定義を記録する。

## severity 5 段階（CodeRabbit 公式）

| Marker | severity | 公式定義 |
|--------|---------|---------|
| 🔴 | Critical | システム障害、セキュリティ侵害、データ損失を引き起こす重大な問題 |
| 🟠 | Major | 機能・パフォーマンスに大きく影響する重要な問題 |
| 🟡 | Minor | 対応すべきだがシステムに致命的な影響はない問題 |
| 🔵 | Trivial | コード品質を高めるための軽微な提案 |
| ⚪ | Info | 情報提供のみ、対応不要 |

## 出典

- [CodeRabbit Code Review Overview](https://docs.coderabbit.ai/guides/code-review-overview)

## vibecorp での扱い

CodeRabbit が出力した severity をそのまま受け取り、vibecorp の捌き基準（`.claude/rules/review-handling.md`）で intent と掛け合わせて修正対象を判定する。

vibecorp 独自の severity 定義は `.claude/rules/severity/claude-action.md` を参照（claude-code-action 用に CodeRabbit からコピーした実体保有版）。

## 変更不可

本ファイルの severity 定義は **CodeRabbit 公式仕様の記録** であり、vibecorp が独自に変更してはならない。CodeRabbit 公式が定義を変更した場合は本ファイルを追従して更新する（その変更は履歴として PR で議論する）。
