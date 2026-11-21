/// What the SDK hands to your analytics. The SDK sends nothing itself.
public enum ConfigEvent: Sendable, Hashable {
    /// A key inside a running experiment was read for the first time this launch. Variants are
    /// counted over these people.
    case exposed(key: String, experiment: String, variant: String, setVersion: Int)
    /// The set or a key could not be used. Once per key, reason and set version.
    case rejected(key: String, reason: RejectReason, setVersion: Int)

    public enum RejectReason: String, Sendable, Hashable {
        /// The whole set is not JSON (key `_set`).
        case parseError = "parse_error"
        /// The set's `schema_version` is newer than this SDK (key `_set`).
        case schemaTooNew = "schema_too_new"
        /// The flag's shape or a value does not fit its type.
        case invalid
        /// The app read the key as another type.
        case typeMismatch = "type_mismatch"
    }

    /// The event name (`config_exposed`, `config_rejected`).
    public var name: String {
        switch self {
        case .exposed: "config_exposed"
        case .rejected: "config_rejected"
        }
    }

    /// The event's parameters, typed.
    public var parameters: [String: ConfigJSON] {
        switch self {
        case let .exposed(key, experiment, variant, setVersion):
            ["key": .string(key), "experiment": .string(experiment), "variant": .string(variant), "set_version": .int(setVersion)]
        case let .rejected(key, reason, setVersion):
            ["key": .string(key), "reason": .string(reason.rawValue), "set_version": .int(setVersion)]
        }
    }
}

/// Where a value came from.
public enum ConfigValueSource: String, Sendable, Hashable {
    /// The key is not in the set, or could not be used: the app's default.
    case fallback
    /// The first rule whose condition matched.
    case rule
    /// The variant assigned in a running experiment.
    case experiment
    /// The flag's default in the set.
    case `default`
}

/// One value read, with where it came from.
public struct ConfigRead: Sendable, Hashable {
    public let key: String
    public let value: ConfigJSON
    public let source: ConfigValueSource
    /// The variant's name when `source` is `.experiment`.
    public let variant: String?
}
