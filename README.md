# swift-app-config

Change typed values in your app without shipping a new build, vary them by device values, and split
them into variants to compare, all decided on the device.

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

> Developed in a private monorepo and copied here one way. Issues are welcome; pull requests are
> not accepted.

## Features

- **Typed reads.** `bool`, `int`, `double`, `string` and `json` (or `decode` into your own type) by
  key, always with your app's default. A key that is missing, has another type or does not fit its
  schema gives the default
- **Fixed for the launch.** The launch uses the set saved earlier, or the bundled one. A newer set
  is fetched and saved for the next launch, so a screen never sees a value change under it
- **Rules on device values.** The first rule whose condition matches (`eq`, `ne`, `in`, `not_in`,
  `gte`, `lte`, `exists`, with `all` / `any`) on `platform`, `app_version`, `build`, `channel`,
  `lang`, `region`, `days_since_first_seen` and your own values
- **Experiments on the device.** Two to four weighted variants; the same person always gets the same
  variant; your own devices get the first. `config_exposed` is recorded the first time a key in a
  running experiment is read in a launch
- **Values only.** The set holds values, never screens or code. New screens ship in a build
- **No dependencies.** Foundation only

## Quick Start

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

A set:

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

## Documentation

- Values are decided in this order: the key is missing, does not fit or has another type (your
  default) → the first matching rule → the assigned variant of a running experiment → the flag's
  default
- The variant: `h = hash32("<project>:<person>:<experiment>:variant")` (FNV-1a over UTF-16 code
  units with murmur3's final mix); the first variant `i` with `h × W < (w₀ + … + wᵢ) × 2³²`
- When the set has `global_holdout: true`, a person with
  `hash32("<project>:<person>:global_holdout") / 2³² < 0.05` gets the first variant of every running
  experiment (source `global_holdout`) and records no `config_exposed`. Your own devices are never in it
- Records: `config_exposed(key, experiment, variant, set_version, propensity, policy_version)` (the
  chance of the variant, and the set's version) and
  `config_rejected(key, reason, set_version)` with `parse_error`, `schema_too_new`, `invalid`,
  `type_mismatch`. Each once per launch
- `ConfigTesting` has `FakeConfigSetSource`, `MemoryConfigStorage` and `RecordingConfigSink`

## Installation

```swift
.package(url: "https://github.com/appgrowstack/swift-app-config.git", .upToNextMinor(from: "0.1.0"))
```

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+

## License

MIT — see [LICENSE](LICENSE).
