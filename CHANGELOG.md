# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-11-23

### Changed

- **Breaking:** a rule may have only `when`, `value`, `requires`, `exclude_app_versions` and
  `app_version`, and needs `when`, `app_version` or both; otherwise the flag is `invalid`.
- A rule or an experiment may carry `app_version`, the range the server resolved from what each
  build contains: per platform `{ "min": "<version>", "exclude": ["<version>", …] }`, each version
  two or three groups of digits. An unreadable one makes the flag `invalid`. A rule matches only when
  the device's `platform` and `app_version` fall in it; an experiment outside it is skipped (the
  flag's default, no `config_exposed`). `requires` and `exclude_app_versions` are not read on the device.

## [0.1.0] - 2026-11-22

### Added

- `AppConfig`: typed reads by key (`bool`, `int`, `double`, `string`, `json`, `decode`) with the app's
  default, a set fixed for the launch, and `refresh()` that saves a newer set for the next launch.
- `ConfigSession`: the decision for one launch (missing or invalid key, rules on device values,
  experiment variants, the flag's default) and the records `config_exposed` and `config_rejected`.
- `ConfigVariant`: the variant assignment shared with the server and the Kotlin SDK.
- `ConfigSetSource`, `BundledConfigSetSource`, `ConfigStorage`, `UserDefaultsConfigStorage`,
  `ConfigContext`.
- `ConfigTesting`: `FakeConfigSetSource`, `MemoryConfigStorage`, `RecordingConfigSink`.
