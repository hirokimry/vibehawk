# CISO 判断記録インデックス

CISO の判断記録の目次。詳細は各アーカイブファイル（`decisions/YYYY-QN.md`）を参照。

## エントリ

- 2026-06-12 — プレイブック新設: playbooks/docs-restructure-review.md — docs 再構成レビュー定石（grep 保全検証・偽陽性判定フロー）を汎用化。PR #345 実績から抽出
- 2026-06-12 — Issue #344 README.md 再構成（intent/docs・挙動不変） — analyst 分裂だが M-1 は Minor 相当（既存配置の問題・今回差分で局所化進まず）。CISO Critical 条件 5 項目全保全確認。脆弱性なし・無条件承認
- 2026-06-12 — Issue #341 .claude/.gitignore skills 例外化 + release SKILL.md 新規 — 両 Major を COO 実機確認（diagnose-guard パスパターン deny）で棄却。脆弱性なし・承認。git check-ignore exit 128 ガード追加を Minor 推奨
- 2026-06-03 — Epic #305 子 Issue A/B/C 自律実行不可領域チェック — 子A/B/C の 3 件とも 6 分類非該当・OK。子B の `id-token: write` は npm provenance 用として既承認
- 2026-05-24 — Issue #219 sticky walkthrough コメント実装 — `issues: write` 追加・`post-sticky-comment.sh` 新規追加。autonomous-restrictions §6 抵触なし・既承認スコープ内・脆弱性なし・承認
- 2026-05-16 — Issue #140 / PR dev/140_rewrite_status_check_positioning — docs 3 ファイルの status check 主軸 positioning 書き換え（コード変更ゼロ）。全 analyst 一致・脆弱性なし・承認
- 2026-05-08 — ship #6 認証設計確定 — Installation Token 権限昇格リスクと approve/request_changes 非使用設計意図を security-principles.md に記録。脆弱性なし・承認
- 2026-05-08 — MVV 制定（Value 4 確定・状態管理ポリシー追記）— SECURITY.md と security-principles.md を具体化。脆弱性なし・設計によるリスク排除を確認
