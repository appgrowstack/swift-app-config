import Foundation

/// A flag's type. `int` is a whole number, `double` any number, `json` an object or an array.
public enum ConfigFlagType: String, Sendable, Hashable, CaseIterable {
    case bool, int, double, string, json

    /// Whether `value` fits this type.
    public func fits(_ value: ConfigJSON) -> Bool {
        switch self {
        case .bool: value.bool != nil
        case .int: value.int != nil
        case .double: value.number != nil
        case .string: value.string.map { $0.count <= 2000 && $0.utf16.count <= 2000 } ?? false
        case .json: value.object != nil || value.array != nil
        }
    }
}

/// One flag of a set, read and checked. A flag that does not fit its schema is skipped with
/// `config_rejected(invalid)` when the app reads its key.
struct ConfigFlag: Sendable {
    struct Rule: Sendable {
        let when: ConfigCondition
        let value: ConfigJSON
    }

    struct Variant: Sendable {
        let name: String
        let weight: Int
        let value: ConfigJSON
    }

    struct Experiment: Sendable {
        let id: String
        let variants: [Variant]
        let startsAt: Date
        let endsAt: Date?

        func isRunning(at now: Date) -> Bool {
            now >= startsAt && (endsAt.map { now < $0 } ?? true)
        }
    }

    struct Invalid: Error {}

    let type: ConfigFlagType
    let defaultValue: ConfigJSON
    let rules: [Rule]
    let experiment: Experiment?

    private static let keys: Set<String> = ["type", "default", "rules", "experiment"]
    private static var name: Regex<Substring> { /^[a-z0-9_]{1,40}$/ }
    private static var experimentID: Regex<Substring> { /^[a-z0-9-]{3,40}$/ }

    init(_ json: ConfigJSON) throws {
        guard let object = json.object, object.keys.allSatisfy(Self.keys.contains),
              let type = object["type"]?.string.flatMap(ConfigFlagType.init(rawValue:)),
              let value = object["default"], type.fits(value) else { throw Invalid() }
        self.type = type
        defaultValue = value
        var rules: [Rule] = []
        if let raw = object["rules"] {
            guard let list = raw.array, list.count <= 30 else { throw Invalid() }
            for item in list {
                guard let rule = item.object, rule.count == 2, let value = rule["value"], type.fits(value) else { throw Invalid() }
                do {
                    rules.append(Rule(when: try ConfigCondition.parse(rule["when"]), value: value))
                } catch {
                    throw Invalid()
                }
            }
        }
        self.rules = rules
        experiment = try object["experiment"].map { try Self.experiment($0, type: type) }
    }

    private static func experiment(_ json: ConfigJSON, type: ConfigFlagType) throws -> Experiment {
        guard let object = json.object, let id = object["id"]?.string, id.wholeMatch(of: experimentID) != nil,
              let list = object["variants"]?.array, (2...4).contains(list.count) else { throw Invalid() }
        let variants = try list.map { item -> Variant in
            guard let v = item.object, let name = v["name"]?.string, name.wholeMatch(of: Self.name) != nil,
                  let weight = v["weight"]?.int, (1...1000).contains(weight),
                  let value = v["value"], type.fits(value) else { throw Invalid() }
            return Variant(name: name, weight: weight, value: value)
        }
        guard Set(variants.map(\.name)).count == variants.count,
              let metric = object["metric"]?.object, metric["event"]?.string != nil, metric["within_hours"]?.number != nil,
              let startsAt = object["starts_at"]?.string.flatMap(ConfigTime.parse) else { throw Invalid() }
        var endsAt: Date?
        switch object["ends_at"] {
        case .null: endsAt = nil
        case .string(let text):
            guard let date = ConfigTime.parse(text) else { throw Invalid() }
            endsAt = date
        default: throw Invalid()
        }
        return Experiment(id: id, variants: variants, startsAt: startsAt, endsAt: endsAt)
    }
}

/// ISO 8601 with an offset (`2026-12-01T00:00:00+09:00`, fractional seconds allowed).
enum ConfigTime {
    static func parse(_ text: String) -> Date? {
        guard text.wholeMatch(of: /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/) != nil else { return nil }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}
