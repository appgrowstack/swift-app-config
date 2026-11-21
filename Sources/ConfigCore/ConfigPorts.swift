import Foundation

/// What fetching a set answered.
public enum ConfigFetchResult: Sendable, Equatable {
    case notModified
    case fetched(Data, etag: String?)
}

/// Where sets come from. The bundled set (``BundledConfigSetSource``) works with no server; a
/// connector fetches from one.
public protocol ConfigSetSource: Sendable {
    /// Throws when the network or the server failed; the set on hand is kept.
    func fetch(etag: String?) async throws -> ConfigFetchResult
}

/// A fetch that got an answer other than a set or "not modified".
public struct ConfigSetFetchFailure: Error, Equatable {
    public let status: Int
    public init(status: Int) { self.status = status }
}

/// The set shipped in the app: a JSON file in the bundle. To change values, ship a new build.
public struct BundledConfigSetSource: ConfigSetSource {
    public struct Missing: Error, Equatable {
        public let resource: String
    }

    /// The bundled set's JSON text (nil when the file is missing).
    public let data: Data?
    private let resource: String

    /// Reads `<resource>.json` from `bundle`.
    public init(resource: String, bundle: Bundle = .main) {
        self.resource = resource
        data = bundle.url(forResource: resource, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }

    /// `<resource>.json` in the main bundle.
    public static func bundled(_ resource: String) -> BundledConfigSetSource {
        BundledConfigSetSource(resource: resource)
    }

    /// A set given as data (tests, or a set built at runtime).
    public init(data: Data) {
        resource = "data"
        self.data = data
    }

    /// The same text gives the same ETag, so a fetch of the same bundle reads as "not modified".
    public var etag: String { "\"bundled-\(data.map { String(ConfigVariant.hash32(String(decoding: $0, as: UTF8.self)), radix: 16) } ?? "none")\"" }

    public func fetch(etag: String?) async throws -> ConfigFetchResult {
        guard let data else { throw Missing(resource: resource) }
        return etag == self.etag ? .notModified : .fetched(data, etag: self.etag)
    }
}


/// What is kept between launches: the last set fetched and its ETag.
public protocol ConfigStorage: Sendable {
    var setData: Data? { get nonmutating set }
    var etag: String? { get nonmutating set }
}

/// `UserDefaults`.
public struct UserDefaultsConfigStorage: ConfigStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "app_config.") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public var setData: Data? {
        get { defaults.data(forKey: prefix + "set") }
        nonmutating set { defaults.set(newValue, forKey: prefix + "set") }
    }

    public var etag: String? {
        get { defaults.string(forKey: prefix + "etag") }
        nonmutating set { defaults.set(newValue, forKey: prefix + "etag") }
    }
}

/// The SDK's device values for rules. Your app adds its own through `AppConfig(facts:)`.
public struct ConfigContext: Sendable, Hashable {
    public var platform: String
    public var appVersion: String
    public var build: String
    /// `appstore`, `testflight`, `debug`, `play`.
    public var channel: String
    public var lang: String
    public var region: String?
    /// The first launch (the earliest you know of).
    public var firstSeenAt: Date
    public var timeZone: TimeZone

    public init(platform: String = "ios", appVersion: String, build: String, channel: String, lang: String, region: String? = nil,
                firstSeenAt: Date, timeZone: TimeZone = .current) {
        self.platform = platform
        self.appVersion = appVersion
        self.build = build
        self.channel = channel
        self.lang = lang
        self.region = region
        self.firstSeenAt = firstSeenAt
        self.timeZone = timeZone
    }

    /// The values under their names in the set's rules, on `now`.
    public func facts(now: Date) -> [String: ConfigJSON] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: firstSeenAt), to: calendar.startOfDay(for: now)).day ?? 0
        var facts: [String: ConfigJSON] = [
            "platform": .string(platform), "app_version": .string(appVersion), "build": .string(build),
            "channel": .string(channel), "lang": .string(lang), "days_since_first_seen": .int(max(0, days))
        ]
        if let region { facts["region"] = .string(region) }
        return facts
    }
}
