import Foundation

/// This package's name and version. A connector that fetches sets from a server reports them.
public enum ConfigSDK {
    /// The package name (`swift-app-config`).
    public static let name = "swift-app-config"
    /// The released version: the newest `## [x.y.z]` section of the CHANGELOG (a test checks it).
    public static let version = "0.1.0"
}

/// Typed values by key, fixed for the launch.
///
/// The launch uses the set saved by an earlier launch, or the bundled one. ``refresh()`` fetches a
/// newer set and saves it for the next launch; values never change while the app runs.
///
/// ```swift
/// let config = AppConfig(
///     source: BundledConfigSetSource(resource: "config"),   // or stack.configSource(fallback:)
///     bundled: .bundled("config"),
///     context: ConfigContext(appVersion: "2.4.0", build: "240", channel: "appstore", lang: "ja", firstSeenAt: installDate),
///     person: { installID },
///     record: { event in analytics.track(event.name, event.parameters) }
/// )
/// let hard = config.bool("paywall_hard", default: false)
/// ```
public final class AppConfig: @unchecked Sendable {
    private let source: any ConfigSetSource
    private let storage: any ConfigStorage
    private let record: @Sendable (ConfigEvent) -> Void
    private let lock = NSLock()
    /// The launch's set and reads.
    public let session: ConfigSession

    /// - Parameters:
    ///   - source: where newer sets come from (the bundled set, or a connector).
    ///   - storage: keeps the last fetched set and its ETag.
    ///   - bundled: the set shipped in the app, used until a set has been fetched once.
    ///   - context: the SDK's device values.
    ///   - facts: your app's device values for rules (`is_premium` and so on). Read once, at the start.
    ///   - person: the person id variants are assigned to.
    ///   - isInternalDevice: your own and testers' devices get the first variant.
    ///   - record: hands `config_exposed` and `config_rejected` to your analytics.
    public init(
        source: any ConfigSetSource,
        storage: any ConfigStorage = UserDefaultsConfigStorage(),
        bundled: BundledConfigSetSource? = nil,
        context: ConfigContext,
        facts: [String: ConfigJSON] = [:],
        person: @Sendable () -> String,
        isInternalDevice: @Sendable () -> Bool = { false },
        now: Date = Date(),
        record: @escaping @Sendable (ConfigEvent) -> Void
    ) {
        self.source = source
        self.storage = storage
        self.record = record
        let saved = storage.setData
        session = ConfigSession(
            set: saved ?? bundled?.data,
            stored: saved == nil ? nil : bundled?.data,
            facts: context.facts(now: now).merging(facts) { sdk, _ in sdk },
            person: person(),
            internalDevice: isInternalDevice(),
            now: now
        )
        flush()
    }

    private func flush() {
        for event in session.takeRecords() { record(event) }
    }

    /// Reads `key`, with `defaultValue` when the set does not have it in this type.
    public func read(_ key: String, as type: ConfigFlagType, default defaultValue: ConfigJSON) -> ConfigRead {
        let read = session.read(key, as: type, fallback: defaultValue)
        flush()
        return read
    }

    public func bool(_ key: String, default defaultValue: Bool) -> Bool {
        read(key, as: .bool, default: .bool(defaultValue)).value.bool ?? defaultValue
    }

    public func int(_ key: String, default defaultValue: Int) -> Int {
        read(key, as: .int, default: .int(defaultValue)).value.int ?? defaultValue
    }

    public func double(_ key: String, default defaultValue: Double) -> Double {
        read(key, as: .double, default: .double(defaultValue)).value.number ?? defaultValue
    }

    public func string(_ key: String, default defaultValue: String) -> String {
        read(key, as: .string, default: .string(defaultValue)).value.string ?? defaultValue
    }

    /// An object or an array.
    public func json(_ key: String, default defaultValue: ConfigJSON) -> ConfigJSON {
        read(key, as: .json, default: defaultValue).value
    }

    /// A `json` flag decoded as `T`; `defaultValue` when it is missing or does not decode.
    public func decode<T: Decodable>(_ key: String, as _: T.Type = T.self, default defaultValue: T) -> T {
        let value = read(key, as: .json, default: .null).value
        guard value != .null, let decoded = try? JSONDecoder().decode(T.self, from: value.data()) else { return defaultValue }
        return decoded
    }

    /// Fetches a newer set and saves it for the next launch. Returns whether a new set was saved.
    /// Failures keep the saved set.
    @discardableResult
    public func refresh() async -> Bool {
        let etag = storage.etag
        guard let result = try? await source.fetch(etag: etag) else { return false }
        guard case .fetched(let data, let newTag) = result else { return false }
        // A set this SDK cannot read is saved too: the next launch records why (config_rejected) and
        // uses the bundled set.
        lock.withLock {
            storage.setData = data
            storage.etag = newTag
        }
        return true
    }
}
