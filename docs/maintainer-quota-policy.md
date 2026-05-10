# vibehawk メンテナー枠（Claude Pro/Max）消費対策ポリシー

> このドキュメントは vibehawk の dogfooding 構造が抱える「メンテナー個人契約枠の消費」問題への公式対策方針を定義する Source of Truth です。
> 本文書は **挙動を規定するポリシー** であり、テンプレートへの反映・コード変更は別 Issue で実装します。

## 1. 背景

vibehawk は MVV.md Value 1「利用者の契約だけで、完結させる」に従い、利用者の Claude Pro / Max OAuth トークン（`CLAUDE_CODE_OAUTH_TOKEN`）を利用してレビューを実行する。

vibehawk リポジトリ自身も dogfooding として `.github/workflows/vibehawk-review.yml` を配置しているため、**vibehawk への PR が出るたびに claude-code-action が起動し、vibehawk メンテナーの Claude Pro/Max 枠を消費する** 構造になっている。

CFO レビュー（2026-05-09）で以下の問題が指摘された:

- OSS 開発が活発になるほど、メンテナー個人の契約枠がボトルネックになる
- ある時点でレート上限に到達するとレビューが停止する
- 利用者リポジトリ向けのテンプレートをそのまま自リポジトリに適用していると、メンテナー枠の保護が考慮されない

vibehawk は「利用者の契約枠保護」を MVV で謳っているが、**OSS としての継続性を担保するためには、メンテナー自身の契約枠も同様に保護される必要がある**。本ドキュメントはその対策ポリシーを定義する。

関連: Issue #69 / Issue #56（dogfooding 運用）

## 2. 対策案の比較

CFO レビューで提示された 4 案を以下の観点で評価する。

| 案 | 内容 | メリット | デメリット | 実装コスト | MVV 整合 |
|---|---|---|---|---|---|
| **A** | workflow の `if:` 条件でメンテナー（OWNER）の PR を除外 | 効果が直接的・確実、設定 1 行で済む | dogfooding（メンテナー自身の PR でレビュー検証）が不可になる | 低 | 高（利用者契約に影響しない） |
| **B** | `concurrency:` 制限でレート抑制 | 既に templates 側で `vibehawk-${{ pr.number }}` を設定済み（同一 PR の重複起動防止） | 異なる PR が同時に来た場合の総量抑制にはならず、メンテナー枠消費の根本解決にはならない | 既設 | 中 |
| **C** | 月間起動回数の上限を workflow に持たせ、超過時はプレースホルダコメントのみ投稿 | メンテナー枠の上限を確実に守れる | 状態管理（GitHub Variables 等）が必要、実装が複雑、利用者リポジトリでも同じ問題が起きるためテンプレート側にも反映が要る | 中〜高 | 高 |
| **D** | dogfooding 専用 workflow を別ファイルで分離（`vibehawk-review.yml` は利用者向け、自リポジトリ用は `vibehawk-review-internal.yml`） | 利用者向け設定とメンテナー保護設定を分離できる | 2 つの workflow を維持する保守負荷、テンプレート同期コスト | 中 | 中 |

## 3. vibehawk 採用案

vibehawk リポジトリ自身は **案 A（OWNER 除外）をメイン採用し、`dogfood` ラベルでオプトイン起動できる escape hatch を併用** する方針とする。

### 3.1. 採用理由

- **MVV Value 1 整合**: メンテナーの Pro/Max 枠を保護することで、vibehawk OSS の継続性を担保する。これは「利用者の契約だけで、完結させる」の精神を vibehawk メンテナー自身にも適用する位置付け
- **実装コスト最小**: workflow の `if:` 条件 1 行で完結する
- **dogfooding を完全に失わない**: `dogfood` ラベル付与で動作確認時のみ起動できる escape hatch を残す
- **利用者向けテンプレートと両立可能**: テンプレート（`templates/.github/workflows/vibehawk-review.yml`）と自リポジトリ用 workflow（`.github/workflows/vibehawk-review.yml`）で `if:` 条件のみを変える運用が可能

### 3.2. 採用しなかった案の理由

- **案 B 単独**: 既に concurrency は設定済みだが、それだけではメンテナー枠消費の根本解決にならない（補完策として併用は継続）
- **案 C**: 状態管理コストが高く、まずは案 A で問題が解決するか検証してから検討する。将来 OSS が大規模化して案 A だけでは足りなくなった段階で再検討する
- **案 D**: 2 つの workflow を維持する保守負荷が高く、テンプレートと自リポジトリ用のドリフトが起きやすい。案 A の `if:` 条件 1 行で同じ目的を達成できるため不採用

### 3.3. 採用案の参考実装（vibehawk リポジトリ自身向け）

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    # メンテナー（OWNER）の PR は枠消費抑制のためスキップ
    # ただし `dogfood` ラベル付きの PR は動作確認用として起動する
    if: >-
      github.event.pull_request.draft == false &&
      (
        github.event.pull_request.author_association != 'OWNER' ||
        contains(github.event.pull_request.labels.*.name, 'dogfood')
      )
```

> **注**: 上記は本ポリシーを反映した参考実装である。`.github/workflows/vibehawk-review.yml` への反映は **別 Issue** で実施する（本 Issue #69 は intent/docs としてポリシー策定のみを担当）。

## 4. 利用者推奨設定

利用者が **メンテナーとして自リポジトリで vibehawk を運用する場合**、自身の Claude Pro/Max 枠の消費が懸念される。以下の対策のいずれか、または組み合わせを推奨する。

### 4.1. パターン 1: メンテナー PR を除外（最小設定、推奨）

利用者リポジトリの `.github/workflows/vibehawk-review.yml` に以下の `if:` を追加する:

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    if: >-
      github.event.pull_request.draft == false &&
      github.event.pull_request.author_association != 'OWNER'
```

メリット: 設定 1 行、即座に効果が出る。
デメリット: メンテナー自身の PR でレビューが走らないため、メンテナー PR は別途人手レビューに頼る必要がある。

### 4.2. パターン 2: ラベルベースのオプトイン

PR に特定ラベル（例: `vibehawk-review`）が付いた場合のみ起動する設定:

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    if: >-
      github.event.pull_request.draft == false &&
      contains(github.event.pull_request.labels.*.name, 'vibehawk-review')
```

メリット: 完全コントロール可能、必要な PR のみ起動。
デメリット: ラベル運用が必要、レビュー漏れリスクあり。

### 4.3. パターン 3: 既存の concurrency と組み合わせ

`templates/.github/workflows/vibehawk-review.yml` には既に `concurrency: vibehawk-${{ pr.number }}` が設定済みで、同一 PR の同時起動による重複消費は防止されている。パターン 1 / 2 と併用することで、より堅牢に枠消費を抑制できる。

## 5. MVV 整合の確認

| MVV 項目 | 本ポリシーとの整合 |
|---|---|
| Value 1「利用者の契約だけで、完結させる」 | ✅ メンテナー（=利用者の一人）の契約枠を保護する設計であり、整合。vibehawk 開発側の追加 API キー・サーバーは不要 |
| Value 2「観察する、書き換えない」 | ✅ 起動条件の制御のみ。コード書き換えやメタデータ操作は発生しない |
| Value 4「公式の道を、迂回せず歩く」 | ✅ GitHub Actions の標準機能（`if:` 条件 / labels）のみで実現、裏 API・スクレイピング不使用 |

## 6. コスト管理ポリシーとの関係

`docs/cost-analysis.md` の段階的劣化（PR サイズによる depth 切替）はレビュー実行時の **コスト最適化** を担う。本ポリシーは **レビュー起動そのものの抑制** を担う、補完関係にある。

| 制御層 | 担当ファイル | 目的 |
|---|---|---|
| 起動抑制 | 本ポリシー（`docs/maintainer-quota-policy.md`） | メンテナー枠消費の上流カット |
| 実行時コスト最適化 | `docs/cost-analysis.md` | 起動した場合のレビュー深度を PR サイズで自動劣化 |

両方を組み合わせることで、vibehawk OSS の継続性とレビュー品質を両立する。

## 7. 関連

- MVV.md Value 1「利用者の契約だけで、完結させる」
- `docs/cost-analysis.md`（PR サイズ段階的劣化、コスト管理ポリシー）
- `docs/POLICY.md`（プロダクト方針 5 大方針）
- Issue #69（本ポリシーの起票元）
- Issue #56（dogfooding 運用、本ポリシーが解決すると Phase 1〜2 の運用負荷が軽減）
- CFO レビュー指摘（2026-05-09）
