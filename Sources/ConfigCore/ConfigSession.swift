import Foundation

/// One launch's set and its reads. The set does not change during the launch, so a screen never
/// sees a value change under it.
///
/// For each read: a key not in the set gives the app's default; a flag that does not fit its schema
/// or has another type gives the app's default and records `config_rejected`; then the first
/// matching rule; then the assigned variant of a running experiment (recording `config_exposed` the
/// first time this launch); then the flag's default.
public final class ConfigSession: @unchecked Sendable {
    public static let schemaVersion = 1

    private struct LoadedSet {
        let project: String
        let version: Int
        let flags: [String: ConfigJSON]
    }

    private let lock = NSLock()
    private let set: LoadedSet?
    private let facts: [String: ConfigJSON]
    private let person: String
    private let internalDevice: Bool
    private let now: Date
    private var parsed: [String: Result<ConfigFlag, ConfigFlag.Invalid>] = [:]
    private var sent: Set<String> = []
    private var exposed: Set<String> = []
    private var pending: [ConfigEvent] = []

    /// - Parameters:
    ///   - set: the set's JSON text for this launch (nil when there is none).
    ///   - stored: the set to use when `set` cannot be used (the one saved earlier, or the bundled one).
    ///   - facts: device values (`platform`, `app_version`, `build`, `channel`, `lang`, `region`,
    ///     `days_since_first_seen`) and the app's own.
    ///   - person: the person id the variants are assigned to.
    public init(set: Data?, stored: Data? = nil, facts: [String: ConfigJSON], person: String, internalDevice: Bool, now: Date) {
        self.facts = facts
        self.person = person
        self.internalDevice = internalDevice
        self.now = now
        var rejected: ConfigEvent?
        self.set = Self.load(set, stored: stored, rejected: &rejected)
        if let rejected { record(rejected) }
    }

    private static func asSet(_ json: ConfigJSON?) -> LoadedSet? {
        guard let object = json?.object, object["schema_version"]?.int == schemaVersion,
              let project = object["project"]?.string, let version = object["version"]?.int,
              let flags = object["flags"]?.object else { return nil }
        return LoadedSet(project: project, version: version, flags: flags)
    }

    private static func load(_ data: Data?, stored: Data?, rejected: inout ConfigEvent?) -> LoadedSet? {
        let fallback = { stored.flatMap(ConfigJSON.parse).flatMap(asSet) }
        guard let data else { return fallback() }
        guard let json = ConfigJSON.parse(data), let object = json.object else {
            rejected = .rejected(key: "_set", reason: .parseError, setVersion: 0)
            return fallback()
        }
        guard object["schema_version"]?.int == schemaVersion else {
            rejected = .rejected(key: "_set", reason: .schemaTooNew, setVersion: object["version"]?.int ?? 0)
            return fallback()
        }
        guard let set = asSet(json) else {
            rejected = .rejected(key: "_set", reason: .parseError, setVersion: 0)
            return fallback()
        }
        return set
    }

    /// The version of the set in use (0 when there is none).
    public var setVersion: Int { self.set?.version ?? 0 }

    private func record(_ event: ConfigEvent) {
        let id: String
        switch event {
        case let .exposed(key, _, _, _): id = "e:\(key)"
        case let .rejected(key, reason, version): id = "r:\(key):\(reason.rawValue):\(version)"
        }
        guard sent.insert(id).inserted else { return }
        pending.append(event)
    }

    /// The records made since the last call, in order.
    public func takeRecords() -> [ConfigEvent] {
        lock.withLock {
            defer { pending.removeAll() }
            return pending
        }
    }

    /// Reads `key` as `type`, with the app's default `fallback`.
    public func read(_ key: String, as type: ConfigFlagType, fallback: ConfigJSON) -> ConfigRead {
        lock.withLock { unlockedRead(key, as: type, fallback: fallback) }
    }

    private func unlockedRead(_ key: String, as type: ConfigFlagType, fallback: ConfigJSON) -> ConfigRead {
        let miss = ConfigRead(key: key, value: fallback, source: .fallback, variant: nil)
        guard let set, let raw = set.flags[key] else { return miss }
        let result = parsed[key] ?? Result { try ConfigFlag(raw) }.mapError { _ in ConfigFlag.Invalid() }
        parsed[key] = result
        guard case .success(let flag) = result else {
            record(.rejected(key: key, reason: .invalid, setVersion: set.version))
            return miss
        }
        guard flag.type == type else {
            record(.rejected(key: key, reason: .typeMismatch, setVersion: set.version))
            return miss
        }
        if let rule = flag.rules.first(where: { $0.when.evaluate(facts) }) {
            return ConfigRead(key: key, value: rule.value, source: .rule, variant: nil)
        }
        if let experiment = flag.experiment, experiment.isRunning(at: now) {
            let index = ConfigVariant.index(project: set.project, person: person, experiment: experiment.id,
                                            weights: experiment.variants.map(\.weight), internalDevice: internalDevice)
            let chosen = experiment.variants[index]
            if exposed.insert(key).inserted {
                record(.exposed(key: key, experiment: experiment.id, variant: chosen.name, setVersion: set.version))
            }
            return ConfigRead(key: key, value: chosen.value, source: .experiment, variant: chosen.name)
        }
        return ConfigRead(key: key, value: flag.defaultValue, source: .default, variant: nil)
    }
}
