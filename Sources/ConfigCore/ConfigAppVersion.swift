import Foundation

/// A version as three numbers. Missing parts count as zero (`3.10` is `3.10.0`).
struct ConfigVersion: Sendable, Hashable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// The device's version: one to four groups of digits; a fourth group is ignored.
    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts.prefix(3) {
            guard Self.isDigits(part), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    /// The form a set writes (`appVersion` in the schema): two or three groups of digits, such as
    /// `3.3` or `3.3.0`.
    init?(appVersion text: String) {
        guard (2...3).contains(text.split(separator: ".", omittingEmptySubsequences: false).count) else { return nil }
        self.init(text)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    private static func isDigits(_ part: Substring) -> Bool {
        !part.isEmpty && part.allSatisfy { ("0"..."9").contains($0) }
    }
}

/// One platform's range in a rule's or an experiment's `app_version`, resolved by core from
/// `requires`: every version from `min` up, except the ones in `exclude`.
struct ConfigVersionRange: Sendable, Equatable {
    let min: ConfigVersion
    let exclude: [ConfigVersion]

    /// `{ "min": "3.3.0", "exclude": ["3.4.0"] }`. Other keys are ignored.
    init?(_ json: ConfigJSON) {
        guard let object = json.object,
              let min = object["min"]?.string.flatMap(ConfigVersion.init(appVersion:)),
              let items = object["exclude"]?.array else { return nil }
        var exclude: [ConfigVersion] = []
        for item in items {
            guard let version = item.string.flatMap(ConfigVersion.init(appVersion:)) else { return nil }
            exclude.append(version)
        }
        self.min = min
        self.exclude = exclude
    }

    /// `min` or newer, and not one of `exclude` (`3.4` is `3.4.0`).
    func contains(_ version: ConfigVersion) -> Bool {
        version >= min && !exclude.contains(version)
    }

    /// The whole `app_version` (platform → range). `nil` unless every value is a readable range;
    /// an empty object is valid and matches no platform.
    static func platforms(_ json: ConfigJSON) -> [String: ConfigVersionRange]? {
        guard let object = json.object else { return nil }
        var ranges: [String: ConfigVersionRange] = [:]
        for (platform, value) in object {
            guard let range = ConfigVersionRange(value) else { return nil }
            ranges[platform] = range
        }
        return ranges
    }

    /// Whether the device's `platform` and `app_version` fall in `ranges`. No ranges: always.
    /// A missing or unreadable device value, or no range for the platform: never.
    static func fits(_ ranges: [String: ConfigVersionRange]?, facts: [String: ConfigJSON]) -> Bool {
        guard let ranges else { return true }
        guard let platform = facts["platform"]?.string, let text = facts["app_version"]?.string,
              let range = ranges[platform], let version = ConfigVersion(text) else { return false }
        return range.contains(version)
    }
}
