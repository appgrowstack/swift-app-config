[English](./README.md) | 日本語

# swift-app-config

アプリの中の型の付いた値を、新しいビルドを出さずに変え、端末の値で変え、案に分けて比べる。決めるのは全部端末。

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

> 非公開のモノリポで作り、ここへは片方向にコピーしている。Issue は受け付ける。プルリクエストは受け付けない。

## できること

- **型で読む。** keyで`bool`・`int`・`double`・`string`・`json`を読む（`decode`で自分の型にもできる）。いつもアプリの既定の値を渡す。keyが無い・型が違う・形が合わないときは既定の値
- **起動の間は変えない。**起動では前に保存した組か同梱の組を使う。新しい組は取って次の起動のために保存するので、画面の途中で値が変わらない
- **端末の値の規則。**条件（`eq`・`ne`・`in`・`not_in`・`gte`・`lte`・`exists`と`all`・`any`）が最初に当たった規則の値。使える値は`platform`・`app_version`・`build`・`channel`・`lang`・`region`・`days_since_first_seen`と自分の値
- **バージョンはビルドの中身から決まる。**規則と実験には、サーバーが要る機能から出した`app_version`を付けられる。中身はOSごとの一番小さいバージョン`min`と除くバージョン`exclude`。端末は自分の`platform`と`app_version`がその範囲に入るかだけを見る。範囲の無いOSには当たらない。規則には`when`か`app_version`の少なくとも片方が要る。`requires`と`exclude_app_versions`はサーバーが使う物で、端末は読まない
- **端末で決める実験。**重みの付いた2〜4つの案。同じ人はいつも同じ案で、自分の端末は最初の案。期間の中で`app_version`が端末に合う実験のkeyを起動で初めて読んだときに`config_exposed`を記録する
- **値だけ。**組は値だけを持ち、画面やコードを持たない。新しい画面はビルドで出す
- **依存なし。** Foundationだけ

## 使い方

```swift
import ConfigCore

let config = AppConfig(
    source: BundledConfigSetSource(resource: "config"),   // or a connector that fetches from a server
    bundled: .bundled("config"),                     // config.json in the app bundle
    context: ConfigContext(appVersion: "2.4.0", build: "240", channel: "appstore", lang: "ja", firstSeenAt: installDate),
    facts: ["is_premium": .bool(isPremium)],
    person: { installID },
    record: { event in analytics.track(event.name, event.parameters) }
)

let hard = config.bool("paywall_hard", default: false)
let headline = config.string("paywall_headline", default: "Keep every book")

Task { await config.refresh() }                       // saved for the next launch
```

組の例:

```json
{
  "schema_version": 1, "project": "reading-memory", "version": 3, "published_at": 0,
  "flags": {
    "paywall_headline": { "type": "string", "default": "Keep every book",
      "rules": [{ "when": { "fact": "lang", "eq": "ja" }, "value": "Remember every book you read" }] },
    "paywall_hard": { "type": "bool", "default": false,
      "experiment": { "id": "paywall-hard-vs-soft", "starts_at": "2026-12-01T00:00:00Z", "ends_at": null,
        "metric": { "event": "purchase_completed", "within_hours": 168 },
        "variants": [{ "name": "soft", "weight": 50, "value": false }, { "name": "hard", "weight": 50, "value": true }] } }
  }
}
```

## 文書

- 値はこの順に決める: keyが無い・形が合わない・型が違う（アプリの既定の値）→ 最初に当たった規則（`app_version`と`when`の両方が合う）→ 期間の中で`app_version`が合う実験の割り当てた案 → フラグの既定の値
- 案の割り当て: `h = hash32("<project>:<person>:<experiment>:variant")`（UTF-16の符号でFNV-1aに、murmur3の最後の混ぜ）。`h × W < (w₀ + … + wᵢ) × 2³²`になる最初の案`i`
- 組の`global_holdout`が`true`のとき、`hash32("<project>:<person>:global_holdout") / 2³² < 0.05`の人は、期間の中の実験で最初の案の値になり（sourceは`global_holdout`）、`config_exposed`を記録しない。自分の端末は入らない
- 記録: `config_exposed(key, experiment, variant, set_version, propensity, policy_version)`（その案を選んだ確率と、組のversion）と、`config_rejected(key, reason, set_version)`（理由は`parse_error`・`schema_too_new`・`invalid`・`type_mismatch`）。どちらも起動ごとに1回
- `ConfigTesting`に`FakeConfigSetSource`・`MemoryConfigStorage`・`RecordingConfigSink`がある

## 入れ方

```swift
.package(url: "https://github.com/appgrowstack/swift-app-config.git", .upToNextMinor(from: "0.1.0"))
```

## 動く環境

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+

## ライセンス

MIT（[LICENSE](LICENSE)）
