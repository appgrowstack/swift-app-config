import Foundation

/// A JSON value: a flag's value, a set read without a fixed shape, or a device value.
///
/// Numbers keep whether they were written as an integer (`.int`) or not (`.double`). When two
/// values are compared, `.int(3)` and `.double(3.0)` are the same number.
public enum ConfigJSON: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ConfigJSON])
    case object([String: ConfigJSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([ConfigJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: ConfigJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Reads JSON text. `nil` when it is not JSON.
    public static func parse(_ data: Data) -> ConfigJSON? {
        try? JSONDecoder().decode(ConfigJSON.self, from: data)
    }

    /// The JSON text (keys sorted).
    public func data() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }

    public var object: [String: ConfigJSON]? { if case .object(let value) = self { value } else { nil } }
    public var array: [ConfigJSON]? { if case .array(let value) = self { value } else { nil } }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var bool: Bool? { if case .bool(let value) = self { value } else { nil } }

    /// An integer, or a number written with a fraction whose value is a whole number.
    public var int: Int? {
        switch self {
        case .int(let value): value
        case .double(let value): value.rounded() == value && abs(value) <= 9_007_199_254_740_991 ? Int(value) : nil
        default: nil
        }
    }

    public var number: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value.isFinite ? value : nil
        default: nil
        }
    }

    /// The same value, comparing numbers by value (`3 == 3.0`).
    public func sameValue(as other: ConfigJSON) -> Bool {
        switch (self, other) {
        case (.int, .int), (.int, .double), (.double, .int), (.double, .double):
            return number == other.number
        case (.array(let a), .array(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.sameValue(as: $1) }
        case (.object(let a), .object(let b)):
            return a.count == b.count && a.allSatisfy { key, value in b[key].map { value.sameValue(as: $0) } ?? false }
        default:
            return self == other
        }
    }
}
