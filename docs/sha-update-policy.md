# claude-code-action SHA 更新ポリシー

vibehawk-review.yml が依存する `anthropics/claude-code-action` の SHA pin を更新する際の評価・適用フローを定義する。CFO + CTO レビュー（2026-05-09、Issue #70）で指摘されたトークン消費回帰・breaking change・セキュリティパッチ追従漏れの 3 リスクを管理することが目的。

## 1. 背景

vibehawk は Mission「レビューツールに追加課金が要らない世界をつくる」を支えるため、利用者の Claude Pro / Max 枠で完結することを設計の前提としている（[`docs/design-philosophy.md`](design-philosophy.md) 参照）。`claude-code-action` の更新は、同じ PR サイズでも消費トークンが変動する可能性があり、利用者の枠を想定外に圧迫するリスクを伴う。

また、SHA pin はサプライチェーン攻撃を防ぐ反面、上流のセキュリティパッチへの追従が遅れるトレードオフを内包する。本ポリシーで両者のバランスを取る。

## 2. 更新トリガー

| トリガー種別 | 評価頻度 | 対応起票 |
|---|---|---|
| 上流のセキュリティ修正リリース | **即時評価**（24 時間以内） | CISO 主導で評価 → 必要なら緊急 PR |
| 機能追加リリース（minor / patch） | 月 1 回評価 | CFO + CTO 評価 → Issue 起票 → PR |
| breaking change リリース（major） | リリース後速やかに評価 | CTO 評価 → 影響範囲調査 Issue 起票 → 対応 PR |

セキュリティ修正は GitHub Security Advisory / `claude-code-action` の `SECURITY.md` を一次情報源とする。

## 3. 必須評価項目

SHA 更新前に以下 3 項目を **必ず** 評価する。記録は `docs/sha-update-history.md` に追記する。

### 3.1 トークン消費の回帰評価（CFO 主管轄）

新 SHA で以下のテスト PR を起動し、消費トークンを記録する:

| カテゴリ | PR サイズ目安 | テスト方法 |
|---|---|---|
| 軽微 | < 10 行変更 | dogfooding リポジトリで小修正 PR を立ち上げる |
| 中規模 | 100 行前後 | 既存中規模 PR の差分で再現 |
| 大規模 | 1000 行前後 | 既存大規模 PR の差分で再現 |

**判定基準**:

- 旧 SHA との比較で **20 % 以上増加** → 利用者向け影響評価ドキュメントを作成し、リリースノートに明記してから適用
- 5 〜 20 % 増加 → CFO に報告、`docs/cost-analysis.md` の Variable Costs テーブルを更新
- 5 % 未満 → 通常更新フロー

### 3.2 breaking change チェック（CTO 主管轄）

- 上流 `anthropics/claude-code-action` の release notes / CHANGELOG を確認する
- `vibehawk-review.yml` で参照している入力パラメータ（`claude_code_oauth_token` / `github_token` / `prompt` / `claude_args`）の互換性を確認する
- dogfooding 環境で動作テストを実施し、サマリコメント投稿が成功することを目視確認する

互換性が崩れる場合は適用を保留し、対応 Issue を起票する。

### 3.3 セキュリティパッチ確認（CISO 主管轄）

- 上流の `SECURITY.md` / GitHub Security Advisory / CVE 情報を確認する
- vibehawk が依存している部分（OAuth Token 受け渡し / GitHub API 呼び出し）にパッチが必要かを判断する
- 必要な場合は他の評価項目より優先して適用する

## 4. 更新フロー

1. 評価結果を `docs/sha-update-history.md` に追記する（評価日 / 旧 SHA / 新 SHA / トークン消費差分 / breaking change 有無 / 適用判定）
2. 影響が大きい場合（トークン消費 20 % 以上増加 / breaking change あり）は `CHANGELOG.md` または GitHub Releases の release notes に明記する
3. 利用者向け推奨アクション（再 dogfooding / 設定見直し等）が必要な場合は `README.md` 末尾の「Status」セクションに追記する
4. SHA 更新 PR を作成し、**CISO + CFO + CTO の 3 名承認** を経てマージする

## 5. CI による検出（任意拡張）

将来的に `.github/workflows/sha-update-check.yml` を追加し、`claude-code-action` の新リリース検知時に自動で Issue を起票する仕組みを検討する。本ポリシー策定時点では手動運用とする（CFO 月次レビュー時にチェック）。

## 6. 関連

- [`docs/cost-analysis.md`](cost-analysis.md): Variable Costs テーブル（トークン消費の影響を反映）
- [`docs/SECURITY.md`](SECURITY.md): npm 配布 / SHA pin の CISO Critical 条件
- [`docs/sha-update-history.md`](sha-update-history.md): 各更新の評価結果記録
- 関連 Issue: #70（本ポリシー策定）, #62（CISO 再承認、SHA 評価フローを Critical 条件として位置づけ）

## 7. 変更履歴

| 日付 | 変更内容 | 関連 Issue |
|---|---|---|
| 2026-05-09 | 初版策定 | #70 |
