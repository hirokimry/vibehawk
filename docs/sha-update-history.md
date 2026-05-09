# claude-code-action SHA 更新履歴

`anthropics/claude-code-action` の SHA pin 更新時の評価結果を記録する。記録ルールは [`docs/sha-update-policy.md`](sha-update-policy.md) を参照。

## 記録フォーマット

各更新エントリは以下のテーブル形式で追記する:

| 項目 | 内容 |
|---|---|
| 評価日 | YYYY-MM-DD |
| 旧 SHA | （短縮形 7 文字 + フル SHA） |
| 新 SHA | （短縮形 7 文字 + フル SHA） |
| 上流リリース | release tag（例: `v0.x.y`） |
| トークン消費差分（軽微 PR） | 旧 → 新（例: 800 → 850, +6 %） |
| トークン消費差分（中規模 PR） | 旧 → 新 |
| トークン消費差分（大規模 PR） | 旧 → 新 |
| breaking change | あり / なし（あればパラメータ変更内容） |
| セキュリティパッチ | あり / なし（あれば CVE 番号 / 対応概要） |
| 適用判定 | 適用 / 保留 / 緊急適用 |
| 承認者 | CISO / CFO / CTO（3 名必須） |
| PR URL | `https://github.com/hirokimry/vibehawk/pull/<N>` |
| 利用者向け追加アクション | 不要 / リリースノート明記 / README 追記 / 再 dogfooding 推奨 |

## 更新履歴

### 初期 SHA（baseline）

| 項目 | 内容 |
|---|---|
| 評価日 | 2026-05-08（PR #50 マージ時点） |
| SHA | `12310e4` (`12310e4417c3473095c957cb311b3cf59a38d659`) |
| 上流リリース | `v1`（`anthropics/claude-code-action` リリースタグ、CodeRabbit 検証 `git tag --contains 12310e4417c3473095c957cb311b3cf59a38d659` で確認） |
| トークン消費差分 | baseline（比較対象なし） |
| breaking change | n/a |
| セキュリティパッチ | n/a |
| 適用判定 | 初期適用 |
| 承認者 | OSS リリース完遂時の C*O 統合議論 |
| PR URL | `https://github.com/hirokimry/vibehawk/pull/50` |
| 利用者向け追加アクション | 不要 |

備考: 本エントリは Issue #70 ポリシー策定時点で baseline として遡及記録したもの。今後の更新は本ポリシー（`docs/sha-update-policy.md`）に従って評価・追記する。

### 今後の更新

（次回更新時に追記）

## 関連

- [`docs/sha-update-policy.md`](sha-update-policy.md): 評価フローの定義
- [`docs/cost-analysis.md`](cost-analysis.md): Variable Costs（トークン消費影響）
- 関連 Issue: #70（本履歴ファイル新設）
