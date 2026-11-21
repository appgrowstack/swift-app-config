import Foundation

/// A rule's condition on device values: one comparison, or `all` / `any` of conditions (three levels
/// at most). Operators: `eq`, `ne`, `in`, `not_in`, `gte`, `lte`, `exists`.
///
/// A device value that is missing matches only `exists: false`. Comparing values of different kinds
/// (a number with a string) does not match. Integers and doubles compare as numbers.
indirect enum ConfigCondition: Sendable {
    case all([ConfigCondition])
    case any([ConfigCondition])
    case leaf(fact: String, op: Operator)

    enum Operator: Sendable {
        case eq(ConfigJSON)
        case ne(ConfigJSON)
        case oneOf([ConfigJSON])
        case noneOf([ConfigJSON])
        case gte(Double)
        case lte(Double)
        case exists(Bool)
    }

    struct Invalid: Error {}

    static let maxDepth = 3
    private static let operators: Set<String> = ["eq", "ne", "in", "not_in", "gte", "lte", "exists"]

    /// Reads a condition. Throws `Invalid` when its shape is wrong.
    static func parse(_ json: ConfigJSON?, depth: Int = 0) throws -> ConfigCondition {
        guard let object = json?.object, !object.isEmpty else { throw Invalid() }
        if object.count == 1, let entry = object.first, entry.key == "all" || entry.key == "any" {
            guard depth < maxDepth, let list = entry.value.array, !list.isEmpty else { throw Invalid() }
            let children = try list.map { try parse($0, depth: depth + 1) }
            return entry.key == "all" ? .all(children) : .any(children)
        }
        guard object.count == 2, let fact = object["fact"]?.string,
              let entry = object.first(where: { $0.key != "fact" }),
              operators.contains(entry.key) else { throw Invalid() }
        return .leaf(fact: fact, op: try parseOperator(entry.key, entry.value))
    }

    private static func isScalar(_ value: ConfigJSON) -> Bool {
        switch value {
        case .bool, .string, .int: true
        case .double(let d): d.isFinite
        default: false
        }
    }

    private static func parseOperator(_ name: String, _ value: ConfigJSON) throws -> Operator {
        switch name {
        case "eq", "ne":
            guard isScalar(value) else { throw Invalid() }
            return name == "eq" ? .eq(value) : .ne(value)
        case "in", "not_in":
            guard let list = value.array, (1...50).contains(list.count), list.allSatisfy(isScalar),
                  Set(list.map(kind)).count == 1 else { throw Invalid() }
            return name == "in" ? .oneOf(list) : .noneOf(list)
        case "gte", "lte":
            guard let number = value.number else { throw Invalid() }
            return name == "gte" ? .gte(number) : .lte(number)
        default:
            guard let flag = value.bool else { throw Invalid() }
            return .exists(flag)
        }
    }

    enum Kind: Hashable { case string, number, bool, other }

    static func kind(_ value: ConfigJSON) -> Kind {
        switch value {
        case .string: .string
        case .int, .double: .number
        case .bool: .bool
        default: .other
        }
    }

    /// `nil` when the kinds differ.
    private static func equals(_ a: ConfigJSON, _ b: ConfigJSON) -> Bool? {
        guard kind(a) == kind(b) else { return nil }
        return a.sameValue(as: b)
    }

    /// One comparison. `nil` when the kinds differ (it does not match).
    static func matches(_ op: Operator, _ value: ConfigJSON?) -> Bool? {
        guard let value else {
            if case .exists(let want) = op { return !want }
            return false
        }
        switch op {
        case .eq(let want): return equals(value, want)
        case .ne(let want): return equals(value, want).map { !$0 }
        case .oneOf(let list), .noneOf(let list):
            guard kind(list[0]) == kind(value) else { return nil }
            let hit = list.contains { equals(value, $0) == true }
            if case .oneOf = op { return hit }
            return !hit
        case .gte(let bound): return value.number.map { $0 >= bound }
        case .lte(let bound): return value.number.map { $0 <= bound }
        case .exists(let want): return want
        }
    }

    /// Left to right: `all` stops at the first miss, `any` at the first hit.
    func evaluate(_ facts: [String: ConfigJSON]) -> Bool {
        switch self {
        case .all(let children): children.allSatisfy { $0.evaluate(facts) }
        case .any(let children): children.contains { $0.evaluate(facts) }
        case .leaf(let fact, let op): Self.matches(op, facts[fact]) == true
        }
    }
}
