# 外部依存リスク監視運用フロー

> [!IMPORTANT]
> 本フローは外部依存サービスの規約・利用条件変更を継続監視するための運用定義。
> ポリシーの定義: [`docs/POLICY.md`](POLICY.md) の「外部依存リスク監視ポリシー」セクション参照。

## 目的

vibehawk の Mission「レビューツールに追加課金が要らない世界をつくる」および Value 1「利用者の契約だけで、完結させる」は、Anthropic が Claude Pro / Max の OAuth ヘッドレス利用経路を維持し続けることを前提としている。

当該経路に以下の変更が発生した場合、API Key 経路を意図的に切った設計のため、移行コストは利用者全員に波及する。

- 規約改定・有償化・Token 自動失効化
- Pro / Max の月額値上げ

本フローはこのリスクを早期検知して被害を最小化することを目的とする。

## 監視対象

| サービス | 監視対象 | 影響度 |
|--------|--------|------|
| Anthropic Claude Pro / Max | OAuth ヘッドレス利用条件、月額価格、Token 失効ポリシー | Mission 直接影響 |
| `anthropics/claude-code-action` | breaking change、SHA pinning 互換性 | workflow 動作影響 |
| GitHub Apps Manifest API | Manifest Flow 仕様変更 | install フロー影響 |
| npm Acceptable Use Policy | 同意プロンプト要件、CLI 配布規約 | 配布性影響 |

## 役割分担

| 役職 | 主務 |
|------|------|
| **CEO** | 監査の主導者。各一次情報源を確認し、変更の有無を判断する |
| **SM** | 監査の日程管理者。月次リマインドを発行し、監査が実施されない場合に CEO へ催促する |
| **CLO** | 規約変更検知時のエスカレーション先（法務・コンプライアンス観点で影響評価を行う） |
| **CFO** | 価格変更検知時のエスカレーション先（コスト影響評価を行う） |

## 月次フロー

### 1. 日程設定（SM）

- 毎月初日（または前回監査日の翌月同日）に CEO に対して監査リマインドを発行する
- 翌月同日が休日の場合は直近の営業日に倒す

### 2. 監査実施（CEO）

各一次情報源を確認する:

- **Anthropic Claude Pro / Max**: [Usage Policy](https://www.anthropic.com/legal/aup)、[Pricing](https://www.anthropic.com/pricing)、Anthropic 公式ブログのリリース
- **`anthropics/claude-code-action`**: GitHub の [release notes](https://github.com/anthropics/claude-code-action/releases) と CHANGELOG
- **GitHub Apps Manifest API**: [GitHub Apps Manifest API docs](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) の deprecation 通知
- **npm Acceptable Use Policy**: [npm Acceptable Use Policies](https://docs.npmjs.com/policies/open-source-terms) の改定告知

### 3. 監査結果の記録（CEO）

[`docs/external-dependency-audit.md`](external-dependency-audit.md) に記録フォーマットに従って当月分エントリを追記する。**変更なし** の場合も「変更なし」と明記して追記する（監査が実施されたことを履歴に残す）。

### 4. 変更検知時のアクション（CEO + 該当 C*O）

| 検知パターン | エスカレーション先 | アクション |
|------------|----------------|---------|
| Anthropic OAuth ヘッドレス利用条件の規約改定 | CEO（24 時間以内） | Mission 直接影響のため最優先で対応評価 |
| Anthropic Pro / Max の月額値上げ | CFO | コスト影響評価、ドキュメント更新 |
| Token 自動失効化 | CEO + CISO | OAuth Token 再取得フロー再設計の可否評価 |
| `claude-code-action` の breaking change | CTO + CFO | [`docs/sha-update-policy.md`](sha-update-policy.md) のフローで評価 |
| GitHub Apps Manifest API の廃止予告 | CTO | 6 ヶ月以内の代替実装 Issue 起票 |
| npm AUP の改定 | CLO | CLI 配布物への影響評価 |

検知した変更について新規 Issue を起票し、影響度に応じた intent ラベル（`intent/security` / `intent/infra` / `intent/docs` 等）を付与する。

## 介入ポイント

以下の状況では運用を中断して CEO の判断を仰ぐ:

| 状況 | タイミング |
|------|-----------|
| Mission 直接影響の規約改定を検知した | 監査中（24 時間以内エスカレーション） |
| 一次情報源が到達不能（403 / 404 / DNS エラー等）の場合 | 監査中（代替情報源の選定） |
| 連続 2 ヶ月監査が実施されない | SM のリマインド発行時（運用見直し） |

## 配置の経緯

本ファイルは Issue #64 の受け入れ条件「監視運用フローを `.claude/rules/` に追加（または既存 SM 役割定義に統合）」に対応するもの。

- `.claude/rules/` には現時点で SM の役割定義ファイルが存在しない。
- 運用フローは vibehawk リポジトリ運営チーム全体（CEO / SM / CLO / CFO / CISO / CTO）が参照するため `docs/` 配下に置く方が経路として自然。
- `docs/POLICY.md` および `docs/external-dependency-audit.md` から本フローを参照する形で運用整合性を担保する。

## 🔗 関連

- ポリシー定義: [`docs/POLICY.md`](POLICY.md)（外部依存リスク監視ポリシー）
- 監査履歴: [`docs/external-dependency-audit.md`](external-dependency-audit.md)
- claude-code-action SHA 更新ポリシー: [`docs/sha-update-policy.md`](sha-update-policy.md)
- claude-code-action SHA 更新履歴: [`docs/sha-update-history.md`](sha-update-history.md)
- MVV: [`MVV.md`](../MVV.md)
- 関連 Issue: #64（本フロー新設）
