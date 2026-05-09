# 認証情報配布方式の設計判断

本ドキュメントは、vibehawk が利用者リポジトリの GitHub Secrets（`CLAUDE_CODE_OAUTH_TOKEN` / `VIBEHAWK_APP_ID` / `VIBEHAWK_PRIVATE_KEY`）の **配布方式** をどう選択したかの判断履歴を、Source of Truth として永続化するものである。

`README.md` / `docs/SECURITY.md` / `docs/POLICY.md` / `docs/design-philosophy.md` 等の各文書は、本ドキュメントを引用する形で運用方針を記述する。

## 1. 採用方針（結論）

- **3 secrets すべてを利用者が GitHub Settings UI で手動登録する**（案 2 採用、CEO 判断 2026-05-09）
- **CLI（`npx vibehawk install`）は secret を一切 touch しない**: `gh secret set` を呼び出さず、メモリ・ファイル・環境変数にも保持しない
- App 作成完了後、CLI は登録手順の **画面誘導のみ** を提供する（GitHub Settings URL を直接表示、Private Key は GitHub の App Settings UI で利用者がダウンロードする）

## 2. 検討した 3 案

| 案 | 内容 | 採否 |
|----|----|----|
| 案 1 全自動 | CLI が `gh secret set` で 3 secrets を自動書込む | ❌ 不採用 |
| **案 2 全手動** | **利用者が GitHub Settings UI で 3 secrets を手動登録する** | ✅ **採用** |
| 案 3 半自動 | OAuth Token は CLI 自動 / Private Key だけ手動 | ❌ 論理整合性不足で不採用 |

採否の経緯:

- **案 3 は論理破綻**: 「個人被害限定」が確定した後、Private Key と OAuth Token は被害規模が同列となり、片方だけ特別扱いする根拠が消えた
- **案 1 は採用候補だったが、業界調査と GitHub 公式ガイドラインを総合的に検討した結果、案 2 を選択**

## 3. メジャーサービス比較表

| サービス | アーキテクチャ | Private Key の所在 | 利用者 secret 登録方法 |
|--------|------------|----------------|------------------|
| Anthropic `claude /install-github-app` | 集中 App or セルフホスト選択可 | Anthropic（公式 App）または利用者（自前 App） | **手動コピペ**（CLI は誘導のみで自動書込しない） |
| CodeRabbit | 集中 SaaS App | CodeRabbit サーバー | 利用者 secret 不要（ベンダー側で完結） |
| Vercel | 集中 SaaS App | Vercel サーバー | 利用者 secret 不要 |
| Snyk | 集中 SaaS App | Snyk サーバー | 利用者 secret 不要 |
| Sentry | 集中 SaaS App | Sentry サーバー | 利用者 secret 不要 |
| Renovate Mend hosted | 集中 SaaS App | Mend サーバー | 利用者 secret 不要 |
| Dependabot | GitHub built-in | GitHub | 利用者 secret 不要 |
| Renovate self-host | セルフホスト App | 利用者の runner | **全手動**（自分で `.pem` 生成・配置） |
| **vibehawk（採用）** | **利用者ごと独立 App** | **利用者リポジトリ** | **全手動コピペ** |

**主要発見**: 「third-party CLI が利用者 GitHub Secrets に自動書込する」設計は、調査範囲のメジャーサービスに **前例ゼロ**。「楽さ」では集中 SaaS が優位だが、独立 App / セルフホスト系は全例「全手動」で揃っている。

vibehawk の独立 App 設計は MVV Value 1（利用者の契約だけで完結）に紐づく必然的選択であり、その帰結として **同業の慣習通り「全手動」を採用** した。

## 4. GitHub 公式ガイドラインの引用

GitHub の公式ドキュメント [Best practices for creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/best-practices-for-creating-a-github-app) は、CLI / native client の Private Key 取扱いに対し明示的な禁止事項を述べている。

> "If your app is a native client, client-side app, or runs on a user device, you must never ship your private key with your app."
>
> "You should not generate installation access tokens since doing so requires a private key. Instead, you should generate user access tokens."

vibehawk の独立 App 設計は、GitHub のガイドライン違反そのものには該当しない（CLI が key を「持つ」のではなく「仲介する」設計）。ただし精神的には同じ警戒対象であり、CLI が Private Key を一瞬でも touch する案 1 は GitHub の推奨方針から外れる。案 2 では CLI は Private Key を一切 touch しないため、ガイドラインに完全準拠する。

関連公式 docs:

- [Best practices for creating a GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/best-practices-for-creating-a-github-app)
- [Managing private keys for GitHub Apps](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps)

## 5. CodeRabbit 事件 (2025-08) の教訓

2025 年 8 月、Kudelski Security が CodeRabbit に対する RCE 攻撃を発表した。CodeRabbit は集中 SaaS App として 100 万リポジトリにインストールされていたが、外部リンタ（Rubocop）のサンドボックス分離不足により、攻撃者が悪意ある PR で **環境変数経由で App Private Key を窃取** した。

- 被害想定範囲: CodeRabbit App がインストールされた **全リポジトリへの write 権限**
- 直接原因: Rubocop が runner プロセス内で動き、**Private Key が同プロセスの環境変数に存在していた**
- 結論教訓（Kudelski 公式）: "Never propagate long-term keys and secrets to the runners."

引用元:

- [How We Exploited CodeRabbit (Kudelski Security, 2025-08)](https://kudelskisecurity.com/research/how-we-exploited-coderabbit-from-a-simple-pr-to-rce-and-write-access-on-1m-repositories/)
- [When CodeRabbit became PwnedRabbit (Endor Labs)](https://www.endorlabs.com/learn/when-coderabbit-became-pwnedrabbit-a-cautionary-tale-for-every-github-app-vendor-and-their-customers)

### vibehawk への含意

vibehawk は利用者ごと独立 App 設計のため、被害規模は CodeRabbit のような「全利用者連鎖」ではなく **個人限定** にとどまる。しかし以下は同列のリスク:

- 鍵が runner / CLI プロセスに存在すること自体が攻撃面
- 個人被害限定でも、**攻撃面（漏れる確率）は緩和されない**

案 2 採用により、CLI が Private Key を touch しない設計となり、CodeRabbit 事件と同クラスの攻撃経路（プロセス環境変数経由・メモリ経由）が **構造的に消滅** する。

## 6. 個人被害限定でも残るリスク（CISO 分析）

「被害規模が個人限定」を所与としても、案 1（CLI 自動書込）には以下のリスクが残る。これらは **「被害規模」ではなく「攻撃面の存在」** に起因し、被害規模緩和では消えない。

| # | リスク | 重大度 | 案 2 で消えるか |
|---|------|------|--------------|
| A-1 | npm サプライチェーン攻撃（パッケージ侵害で 3 secrets 抜かれる） | 🔴 Critical | ✅ 完全に消える |
| C-1 | typosquatting（類似名 npm パッケージで誘導） | 🔴 Critical | ✅ 完全に消える |
| F-1 | gh CLI 権限の借用（CLI 実行中、利用者の GitHub 全権限を握れる立場） | 🟠 Major | ✅ 完全に消える |
| A-2 | CLI 実装バグでの漏洩（ログ・一時ファイル・stdout） | 🟠 Major | ✅ 完全に消える |
| E | 単一障害点（3 secret が同一コードパスを通る） | 🟠 Major | ✅ 完全に消える |
| D-1 | ブラックボックス問題（CLI が何をしたか利用者から見えない） | 🟠 Major | ✅ 完全に消える |
| G-1 | Anthropic OAuth 規約違反可能性（third-party CLI 経由のトークン中継） | 🟠 Major | ✅ 完全に消える |
| その他 | メモリ・swap・バックアップツール取り込み等 | 🟡 Minor | ✅ ほぼ全て消える |

これらの Critical / Major リスクは、いずれも **CLI を使わなければ攻撃面が存在しない**。実装による軽減ではなく、設計選択（案 2 採用）で構造的に消滅する点が決定的に重要。

severity 判定基準は `.claude/rules/severity/coderabbit.md` および `.claude/rules/severity/claude-action.md` に従う（CodeRabbit 公式 5 段階）。

## 7. MVV との整合

[`MVV.md`](../MVV.md) で定義された各 Value との整合性:

- **Value 1「利用者の契約だけで、完結させる」**: 利用者が自分の手で secret を登録する経路は、CEO のサーバー・CLI が認証情報を仲介する経路と比べて、より純粋に「利用者の契約内で完結」する
- **Value 2「観察する、書き換えない」**: CLI が利用者リポジトリの状態（secrets ストア）を書き換えないことと一致。secrets は GitHub のリポジトリ状態の一部であり、書き換え禁止の精神に整合する
- **Value 4「公式の道を、迂回せず歩く」**: GitHub Settings UI という公式に案内された secret 登録経路を最大限活用する。CLI による迂回登録経路を作らない

vibehawk が「利用者ごと独立 App」を採用した経緯は、MVV Value 1 を満たしながら CodeRabbit 型の集中漏洩リスクも避ける、構造的に唯一の解として導出されている（[`design-philosophy.md`](design-philosophy.md) 参照）。本ドキュメントが扱う「secret 配布方式」は、その独立 App 設計の上に成立する戦術選択である。

## 8. トレードオフ（採用後の利用者体験）

### 利用者ステップの増加

案 2 では利用者ステップがコピペ 3 回（OAuth Token / App ID / Private Key）増える。

| 比較対象 | 利用者の secret 登録ステップ |
|---------|------------------------|
| CodeRabbit / Vercel / Snyk 等の集中 SaaS | 0 回（OAuth インストールのみ） |
| Anthropic claude-code-action（公式 App） | 1 回（OAuth Token） |
| **vibehawk（採用）** | **3 回（OAuth Token / App ID / Private Key）** |
| Renovate self-host | 同等または以上 |

### 競合との実態整理

導入摩擦の比較は **同種アーキテクチャの中で行う** べきである:

- vibehawk の競合は実態として **Renovate self-host や Anthropic 自前 App パターン**
- 集中 SaaS（CodeRabbit 等）と比べて摩擦が大きいのは、それらが利用者契約内に閉じない（vibehawk の MVV と相容れない）構造であり、比較対象として適切でない
- 独立 App / セルフホスト系の慣習に照らせば、**vibehawk の摩擦は同業並み**

### 採用後の CLI 動作（要約）

```text
$ npx vibehawk install --owner alice
✅ App `vibehawk-for-alice` を作成しました（GitHub Manifest Flow）
   - App ID: 1234567

次の手順を順番に実施してください:

1. App Private Key の取得（GitHub UI）
   → https://github.com/settings/apps/vibehawk-for-alice
   → "Generate a private key" → .pem ダウンロード

2. リポジトリ Secrets の登録（GitHub UI）
   → https://github.com/alice/your-repo/settings/secrets/actions/new
   → 以下 3 つの secret を順に登録:
       - VIBEHAWK_APP_ID:        （上記 App ID をコピペ）
       - VIBEHAWK_PRIVATE_KEY:   （ダウンロードした .pem の内容をコピペ）
       - CLAUDE_CODE_OAUTH_TOKEN: （`claude setup-token` で取得）

3. workflow の配置
   → 提供される vibehawk-review.yml を .github/workflows/ に配置
```

CLI は登録代行をしない。利用者が GitHub UI で操作する。

## 9. 関連 Issue / PR / 議論

- [#72 議論本体（決定記録）](https://github.com/hirokimry/vibehawk/issues/72)
- [#1 当初のアーキテクチャ設計（公式 App 方式）](https://github.com/hirokimry/vibehawk/issues/1)
- [#7 公式 App 方式の skeleton 実装（CLOSED）](https://github.com/hirokimry/vibehawk/issues/7)
- [#22 公式 App 方式の実装破綻と却下（CLOSED）](https://github.com/hirokimry/vibehawk/issues/22)
- [#25 利用者ごと独立 App の命名統制（CLOSED）](https://github.com/hirokimry/vibehawk/issues/25)
- [#26 OAuth Token 自動登録の shipped 実装（CLOSED, 本決定で撤去対象）](https://github.com/hirokimry/vibehawk/issues/26)
- [#60 App credentials 自動登録（cancel）](https://github.com/hirokimry/vibehawk/issues/60)
- [#61 docs 全面改訂（本ドキュメント反映先）](https://github.com/hirokimry/vibehawk/issues/61)
- [#62 CISO 再承認](https://github.com/hirokimry/vibehawk/issues/62)
- [#66 `--repo` フラグ統合設計（cancel）](https://github.com/hirokimry/vibehawk/issues/66)
- [#68 法務整理](https://github.com/hirokimry/vibehawk/issues/68)
- [#74 cli/oauth.js 自動登録撤去](https://github.com/hirokimry/vibehawk/issues/74)

## 10. 改訂履歴

| 日付 | 改訂内容 | 関連 Issue |
|------|------|-----|
| 2026-05-09 | 初版作成（案 2 採用の Source of Truth として） | #73 |
