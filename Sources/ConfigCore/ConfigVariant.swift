/// The variant assignment (the same formula on the server and in every SDK).
///
/// `h = hash32("<project>:<person>:<experiment>:variant")` (FNV-1a over UTF-16 code units, then
/// murmur3's final mix), `W` = the sum of the weights. The person gets the first variant `i` with
/// `h × W < (w₀ + … + wᵢ) × 2³²`, compared as integers. An internal device always gets the first
/// variant.
public enum ConfigVariant {
    public static func hash32(_ input: String) -> UInt32 {
        var hash: UInt32 = 0x811c9dc5
        for unit in input.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x01000193
        }
        hash ^= hash >> 16
        hash = hash &* 0x85ebca6b
        hash ^= hash >> 13
        hash = hash &* 0xc2b2ae35
        hash ^= hash >> 16
        return hash
    }

    public static func key(project: String, person: String, experiment: String) -> String {
        "\(project):\(person):\(experiment):variant"
    }

    /// The index of the assigned variant. `weights` are 1…1000, two to four of them.
    public static func index(project: String, person: String, experiment: String, weights: [Int], internalDevice: Bool) -> Int {
        if internalDevice { return 0 }
        let h = UInt64(hash32(key(project: project, person: person, experiment: experiment)))
        let total = UInt64(weights.reduce(0, +))
        var cumulative: UInt64 = 0
        for (i, weight) in weights.enumerated() {
            cumulative += UInt64(weight)
            if h * total < cumulative << 32 { return i }
        }
        return weights.count - 1
    }

    /// The share of people in the product-wide holdout (R10).
    public static let globalHoldout = 0.05

    /// Whether the person is in the product-wide holdout (R10):
    /// `hash32("<project>:<person>:global_holdout") / 2^32 < 0.05`. The owner's device never is.
    public static func inGlobalHoldout(project: String, person: String, internalDevice: Bool) -> Bool {
        !internalDevice && Double(hash32("\(project):\(person):global_holdout")) / 4_294_967_296 < globalHoldout
    }

    /// The chance of the assigned variant: its weight over the sum (the owner's device: 1 for the first).
    /// Rounded to 6 places, as the shared cases and the server compare.
    public static func propensity(weights: [Int], index: Int, internalDevice: Bool) -> Double {
        if internalDevice { return index == 0 ? 1 : 0 }
        let total = weights.reduce(0, +)
        guard total > 0, weights.indices.contains(index) else { return 0 }
        return (Double(weights[index]) / Double(total) * 1_000_000).rounded() / 1_000_000
    }

    /// `hash32 / 2^32`, for display only.
    public static func unit(project: String, person: String, experiment: String) -> Double {
        Double(hash32(key(project: project, person: person, experiment: experiment))) / 4_294_967_296
    }
}
