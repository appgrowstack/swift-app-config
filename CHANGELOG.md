# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-21

### Added

- `AppConfig`: typed reads by key (`bool`, `int`, `double`, `string`, `json`, `decode`) with the app's
  default, a set fixed for the launch, and `refresh()` that saves a newer set for the next launch.
- `ConfigSession`: the decision for one launch (missing or invalid key, rules on device values,
  experiment variants, the flag's default) and the records `config_exposed` and `config_rejected`.
- `ConfigVariant`: the variant assignment shared with the server and the Kotlin SDK.
- `ConfigSetSource`, `BundledConfigSetSource`, `ConfigStorage`, `UserDefaultsConfigStorage`,
  `ConfigContext`.
- `ConfigTesting`: `FakeConfigSetSource`, `MemoryConfigStorage`, `RecordingConfigSink`.
