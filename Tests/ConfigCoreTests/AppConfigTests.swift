import ConfigCore
import ConfigTesting
import Foundation
import Testing

private func set(version: Int, headline: String) -> Data {
    Data(#"{"schema_version":1,"project":"reading-memory","version":\#(version),"published_at":0,"flags":{"paywall_headline":{"type":"string","default":"\#(headline)"}}}"#.utf8)
}

private let context = ConfigContext(appVersion: "2.4.0", build: "240", channel: "appstore", lang: "ja", region: "JP",
                                    firstSeenAt: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "Asia/Tokyo")!)

struct AppConfigTests {
    @Test func usesTheBundledSetUntilOneIsSavedAndTheFetchedSetFromTheNextLaunch() async {
        let storage = MemoryConfigStorage()
        let source = FakeConfigSetSource([.success(.fetched(set(version: 2, headline: "new"), etag: "\"v2\""))])
        let bundled = BundledConfigSetSource(data: set(version: 1, headline: "bundled"))
        let sink = RecordingConfigSink()
        let first = AppConfig(source: source, storage: storage, bundled: bundled, context: context, person: { "p1" }, record: sink.record)
        #expect(first.string("paywall_headline", default: "app") == "bundled")
        #expect(await first.refresh())
        // The running launch keeps its set.
        #expect(first.string("paywall_headline", default: "app") == "bundled")
        let next = AppConfig(source: source, storage: storage, bundled: bundled, context: context, person: { "p1" }, record: sink.record)
        #expect(next.string("paywall_headline", default: "app") == "new")
        #expect(next.session.setVersion == 2)
        // The saved ETag goes with the next fetch; 304 keeps the saved set.
        #expect(await next.refresh() == false)
        #expect(source.etags == [nil, "\"v2\""])
        #expect(storage.setData == set(version: 2, headline: "new"))
    }

    @Test func failuresKeepTheSavedSet() async {
        struct Offline: Error {}
        let storage = MemoryConfigStorage(set: set(version: 3, headline: "saved"), etag: "\"v3\"")
        let config = AppConfig(source: FakeConfigSetSource([.failure(Offline())]), storage: storage, context: context, person: { "p1" }, record: { _ in })
        #expect(await config.refresh() == false)
        #expect(storage.setData == set(version: 3, headline: "saved"))
        #expect(config.string("paywall_headline", default: "app") == "saved")
    }

    @Test func typedReadsAndRecords() {
        let data = Data(#"""
        {"schema_version":1,"project":"reading-memory","version":5,"published_at":0,"flags":{
          "plans":{"type":"int","default":2,"rules":[{"when":{"fact":"days_since_first_seen","gte":3},"value":3}]},
          "ratio":{"type":"double","default":0.5},
          "on":{"type":"bool","default":true},
          "pages":{"type":"json","default":["welcome","goal"]},
          "premium_only":{"type":"bool","default":false,"rules":[{"when":{"fact":"is_premium","eq":true},"value":true}]}
        }}
        """#.utf8)
        let sink = RecordingConfigSink()
        let config = AppConfig(source: FakeConfigSetSource(), storage: MemoryConfigStorage(set: data), context: context,
                               facts: ["is_premium": .bool(true)], person: { "p1" }, record: sink.record)
        #expect(config.int("plans", default: 0) == 3)
        #expect(config.double("ratio", default: 0) == 0.5)
        #expect(config.bool("on", default: false))
        #expect(config.json("pages", default: .array([])) == .array([.string("welcome"), .string("goal")]))
        #expect(config.decode("pages", default: [String]()) == ["welcome", "goal"])
        #expect(config.bool("premium_only", default: false))
        #expect(config.string("on", default: "x") == "x")
        #expect(sink.events == [.rejected(key: "on", reason: .typeMismatch, setVersion: 5)])
        #expect(ConfigSDK.name == "swift-app-config")
    }

    @Test func theBundledSourceAnswersNotModifiedForItsOwnETag() async throws {
        let bundled = BundledConfigSetSource(data: set(version: 1, headline: "a"))
        #expect(try await bundled.fetch(etag: nil) == .fetched(set(version: 1, headline: "a"), etag: bundled.etag))
        #expect(try await bundled.fetch(etag: bundled.etag) == .notModified)
        await #expect(throws: BundledConfigSetSource.Missing.self) { try await BundledConfigSetSource(resource: "nothing").fetch(etag: nil) }
    }
}
