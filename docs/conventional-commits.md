# Conventional Commits — vibecorp 厳格定義

vibecorp は Conventional Commits (CC) v1.0.0 標準仕様を採用する。本ドキュメントは CC 11 種の vibecorp での厳格な解釈と、絵文字との 1:1 対応を定義する。

## 主従関係（絶対条件）

| 役割 | 軸 |
|------|---|
| **主**（vibecorp 独自要件、判定の起点） | **intent ラベル** |
| **従**（業界標準、機械可読の保険） | **CC prefix** |

判定フロー: **intent → CC prefix の順で決める**。逆引き（CC prefix → intent）は行わない。

intent ラベル定義の SoT は `.claude/rules/intent-labels.md` を参照。

### 厳守事項（破ると判定軸が歪む）

1. **起票・コミット時の判定フローは必ず `intent → prefix` の順で行う**
   - 先に intent を決める（vibecorp の判定軸として）
   - 次に対応する CC prefix を選ぶ（CC 標準 11 種の中から、その intent に対応するものを選ぶ）
   - **逆順（prefix から intent を決める）は禁止**
2. **「prefix が複数 intent を持つ」という見方は禁止**
   - 「intent に対応する prefix が複数ある」が正しい
   - 例: `intent/security` に対応するのは `fix` / `feat` / `chore`（intent から見た複数）
3. **逆引き表（prefix → intent）は docs に載せない**
   - 主従関係を狂わせるため
   - docs には正引き表（intent → prefix）のみ載せる
4. **議論・設計の順序も主従に従う**
   - intent ラベルを先に確定 → その後で対応 prefix を確定
   - 逆順での議論は禁止

### 違反時の影響例

過去の議論で「`security:` 単独 prefix を採用しない」と判断したのは、CC 標準（業界都合）を主軸に置いて vibecorp 独自要件 `intent/security` を見失いそうになった典型例。CC 拡張に飛びつかずに `intent/security` を主軸に据え直し、CC は `fix(security): ...` 等の scope 表記で吸収する形に着地した。**prefix 主導で議論しそうになったら本セクションに立ち戻る**。

## CC 11 種の vibecorp 厳格定義

### feat — 新機能追加

- **CC 公式**: 新機能をアプリ・ライブラリに追加する commit
- **vibecorp 厳格定義**: **観測可能な挙動が新たに加わる変更**。新規スキル / 新規フック / 新規エンドポイントなど。新機能追加が伴わない場合は使わない
- **絵文字**: ✨

### fix — バグ修正

- **CC 公式**: バグ修正の commit
- **vibecorp 厳格定義**: 既存挙動の不具合を最小修正で直す変更
- **特に注記**: **セキュリティ脆弱性の修正もここに含める**（`fix(security): ...` の scope 表記で明示）
- **絵文字**: 🐛

### perf — パフォーマンス改善

- **CC 公式**: コード変更によりパフォーマンスを改善する commit
- **vibecorp 厳格定義**: **観測可能な性能特性が変わる変更**
- **特に注記**: **観測不可能な内部最適化のみで挙動完全不変なら `refactor` を使う**
- **絵文字**: ⚡

### refactor — リファクタリング 🔴 厳格化大

- **CC 公式**: バグ修正でも機能追加でもないコード変更（挙動が変わる可能性も含む）
- **vibecorp 厳格定義**: **プロダクトの挙動を変えない構造改善のみ**
- **特に厳格化される部分**:
  - 公開 API のリネーム → `refactor` 不可、`feat` または `fix` へ
  - 観測可能な挙動が変わる内部実装変更 → `refactor` 不可
  - 内部関数のリネーム → `refactor` OK
  - 凝集度・命名一貫性の改善 → `refactor` OK
- **絵文字**: 🔄

### style — フォーマット・スタイル修正

- **CC 公式**: コードの意味に影響しない変更（空白、フォーマット、セミコロンなど）
- **vibecorp 厳格定義**: コード意味を変えないフォーマット変更のみ。挙動不変として扱う
- **特に注記**: vibecorp では **`intent/refactor` ラベルに統合される**（`style` 単独の intent は持たない）
- **絵文字**: 💄

### docs — ドキュメント

- **CC 公式**: ドキュメントのみの変更
- **vibecorp 厳格定義**: コード本体の動作に影響しないドキュメント変更（`docs/` / `README.md` / コード内コメント）
- **特に注記**: **docs 内のサンプルコードがコード本体に影響する場合は `feat` または `fix` 等で扱う**（純粋な docs ではない）
- **絵文字**: 📖

### test — テスト

- **CC 公式**: 不足テストの追加または既存テストの修正
- **vibecorp 厳格定義**: `tests/` 配下の変更のみ。本番コードに触れない
- **特に厳格化される部分**: **テスト追加時に本番コードのバグも修正する場合は別 commit に分ける**（テスト追加 = `test`、本番コード修正 = `fix` の二段階）
- **絵文字**: 🧪

### ci — CI 設定

- **CC 公式**: CI 設定ファイル・スクリプトの変更
- **vibecorp 厳格定義**: `.github/workflows/` などの CI 設定変更のみ。本番コードに影響しない前提
- **絵文字**: 🔧

### chore — 雑務 🔴 厳格化大

- **CC 公式**: ソース・テストを変更しないその他の変更
- **vibecorp 厳格定義**: 挙動不変な雑務のみ
- **特に厳格化される部分**:
  - 依存パッケージのパッチ・マイナー更新で API 不変 → `chore` OK
  - **依存パッケージのメジャー更新で API が変わる → `chore` 不可、`feat` または `fix` へ**
  - lint ルール追加 → `chore` OK
  - 設定ファイルのコメント整理 → `chore` OK
- **絵文字**: ⚙️

### build — ビルドシステム 🔴 厳格化大

- **CC 公式**: ビルドシステムや外部依存に影響する変更
- **vibecorp 厳格定義**: 挙動不変なビルド設定のみ
- **特に厳格化される部分**:
  - **ビルドフラグ変更でランタイム挙動が変わる場合は `build` 不可、`perf` または `feat` へ**
  - ビルド設定の純粋整理で成果物変わらず → `build` OK
- **絵文字**: 📦

### revert — 差し戻し

- **CC 公式**: 過去の commit を取り消す commit
- **vibecorp 厳格定義**: 既検証コードへの差し戻しのみ
- **絵文字**: ⏪
- **intent ラベル**: `intent/bugfix` を付与する（差し戻しの本質は「直前の commit が引き起こした問題を取り消す」= バグ修正の一形態）

## intent ラベル → CC prefix 対応表（M:N）

intent ラベル（主）から CC prefix（従）を選ぶ際の対応表。

| intent ラベル | 対応する CC prefix |
|--------------|------------------|
| `intent/feature` | `feat` |
| `intent/bugfix` | `fix`, `revert`（差し戻しは regression 修正の一形態） |
| `intent/performance` | `perf`, `feat`（性能向上目的の機能）, `fix`（パフォーマンス系バグ） |
| `intent/security` | `fix`（脆弱性修正）, `feat`（セキュリティ機能追加）, `chore`（依存パッケージのセキュリティアップデート） |
| `intent/refactor` | `refactor`, `style` |
| `intent/infra` | `test`, `ci`, `chore`, `build` |
| `intent/docs` | `docs` |

### CC 11 種の網羅性（読み手向け参考、判定では使わない）

CC 11 種すべてが少なくとも 1 つの intent に対応する:

- feat → intent/feature, intent/performance, intent/security
- fix → intent/bugfix, intent/performance, intent/security
- perf → intent/performance
- refactor → intent/refactor
- style → intent/refactor
- docs → intent/docs
- test → intent/infra
- ci → intent/infra
- chore → intent/infra, intent/security
- build → intent/infra
- revert → intent/bugfix（差し戻しは regression 修正の一形態）

⚠️ **逆引き（CC prefix → intent）は判定で使わない。** 主従関係を狂わせる。

### 検証時にあえて除外したエッジケース

| ケース | 扱い | 理由 |
|---|---|---|
| `perf` を `intent/security` に振らない | NG | timing attack 対策のような「性能 + 脆弱性」は `fix(security): ...` で扱う |
| `docs` / `test` / `ci` を `intent/security` に振らない | NG | プロダクト挙動を変えない（挙動不変系のまま）。セキュリティドキュメントは `intent/docs`、セキュリティテストは `intent/infra` |
| `build` を `intent/security` に振らない | NG | ランタイム挙動が変わる `build` 変更は vibecorp 厳格定義により `build` 不可（`feat` / `fix` に分類変更） |

## タイトル形式

PR / Issue / commit のタイトルは以下のいずれか:

```text
{絵文字} {CC prefix}: {動作主語の説明}
{絵文字} {CC prefix}({scope}): {動作主語の説明}
```

例:
- `✨ feat: AI レビューワークフローが配布されるようになった`
- `🐛 fix(install): 既存 REVIEW.md が初回 install で保護されるようになった`
- `📖 docs: cost-analysis に warning セクションが追加された`

説明文は `.claude/rules/communication.md` の動作主語規約に従う。

## 1 PR 1 intent 厳守

- 1 つの Issue / PR には intent ラベルを **1 つだけ** 付与する
- 複数 intent にまたがる変更は Issue を分割する
- `templates/.github/workflows/ai-review.yml` の `intent-label-check` ジョブが機械的に強制（**0 件または 2 件以上で fail コメント**）

## 関連

- intent ラベル定義の SoT: `.claude/rules/intent-labels.md`
- communication 規約: `.claude/rules/communication.md`
- severity 公式定義: `.claude/rules/severity/coderabbit.md`
- severity 実体版: `.claude/rules/severity/claude-action.md`
- レビュー捌き基準: `.claude/rules/review-handling.md`
- レビュー観点: `.claude/rules/review-observations.md`
