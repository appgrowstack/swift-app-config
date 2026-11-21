import ConfigCore
import ConfigTesting
import Foundation
import Testing

/// Runs every case in `schema/cases/config` and the vectors in `schema/cases/experiment/variant.json`
/// (copied by `scripts/sync-cases.sh`). TypeScript and Kotlin read the same files.
struct SharedCasesTests {
    static let cases = Bundle.module.url(forResource: "Cases", withExtension: nil)!
    static let directory = cases.appending(path: "config")

    static let names: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }()

    static func read(_ url: URL) throws -> [String: ConfigJSON] {
        let data = try Data(contentsOf: url)
        return try #require(ConfigJSON.parse(data)?.object)
    }

    /// Order-free comparison of records: canonical JSON text, numbers as numbers.
    static func canonical(_ value: ConfigJSON) -> String {
        switch value {
        case .int(let i): String(i)
        case .double(let d): d.rounded() == d && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .object(let o): "{" + o.keys.sorted().map { "\($0):\(canonical(o[$0]!))" }.joined(separator: ",") + "}"
        case .array(let a): "[" + a.map(canonical).joined(separator: ",") + "]"
        default: String(decoding: value.data(), as: UTF8.self)
        }
    }

    @Test func thereAreCases() {
        #expect(Self.names.count > 15)
    }

    @Test(arguments: names)
    func sharedCase(_ name: String) throws {
        let c = try Self.read(Self.directory.appending(path: "\(name).json"))
        let set: Data? = c["set"].map { $0.data() } ?? c["set_raw"]?.string.map { Data($0.utf8) }
        let now = try #require(c["now"]?.string.flatMap { text -> Date? in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: text)
        })
        let person = try #require(c["person_id"]?.string)
        let session = ConfigSession(
            set: set,
            stored: c["stored_set"].map { $0.data() },
            facts: c["facts"]?.object ?? [:],
            person: person,
            internalDevice: c["internal"]?.bool ?? false,
            now: now
        )
        let reads = try #require(c["reads"]?.array)
        let expect = try #require(c["expect"]?.object)
        let values = try #require(expect["values"]?.array)
        #expect(reads.count == values.count)
        for (read, want) in zip(reads, values) {
            let r = try #require(read.object)
            let type = try #require(r["type"]?.string.flatMap(ConfigFlagType.init(rawValue:)))
            let key = try #require(r["key"]?.string)
            let fallback = try #require(r["fallback"])
            let got = session.read(key, as: type, fallback: fallback)
            let w = try #require(want.object)
            let wantValue = try #require(w["value"])
            #expect(got.key == w["key"]?.string, "\(name) key")
            #expect(got.value.sameValue(as: wantValue), "\(name) value \(got.value)")
            #expect(got.source.rawValue == w["source"]?.string, "\(name) source")
            #expect(got.variant == w["variant"]?.string, "\(name) variant")
        }
        let records = session.takeRecords().map { event in
            Self.canonical(.object(["name": .string(event.name), "params": .object(event.parameters)]))
        }.sorted()
        let wantRecords = (expect["records"]?.array ?? []).map(Self.canonical).sorted()
        #expect(records == wantRecords, "\(name) records")
    }

    @Test func variantVectors() throws {
        let file = try Self.read(Self.cases.appending(path: "experiment/variant.json"))
        let vectors = try #require(file["vectors"]?.array)
        #expect(!vectors.isEmpty)
        for vector in vectors {
            let v = try #require(vector.object)
            let input = try #require(v["input"]?.object)
            let project = try #require(input["project"]?.string)
            let person = try #require(input["person_id"]?.string)
            let experiment = try #require(input["experiment"]?.string)
            let weights = try #require(input["weights"]?.array).compactMap(\.int)
            let internalDevice = input["internal"]?.bool ?? false
            let key = ConfigVariant.key(project: project, person: person, experiment: experiment)
            #expect(key == v["key"]?.string)
            #expect(Int(ConfigVariant.hash32(key)) == v["hash32"]?.int)
            let index = ConfigVariant.index(project: project, person: person, experiment: experiment, weights: weights, internalDevice: internalDevice)
            #expect(index == v["expect"]?.object?["index"]?.int, "\(v["description"]?.string ?? "")")
        }
    }
}
