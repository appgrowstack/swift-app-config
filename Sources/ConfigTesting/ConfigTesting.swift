import ConfigCore
import Foundation

/// A source that answers what you queue, and remembers the ETags it was asked with.
public final class FakeConfigSetSource: ConfigSetSource, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<ConfigFetchResult, Error>]
    private var asked: [String?] = []

    public init(_ answers: [Result<ConfigFetchResult, Error>] = []) { self.answers = answers }

    /// The ETags passed to `fetch`, in order.
    public var etags: [String?] { lock.withLock { asked } }

    public func enqueue(_ answer: Result<ConfigFetchResult, Error>) { lock.withLock { answers.append(answer) } }

    public func fetch(etag: String?) async throws -> ConfigFetchResult {
        let next = lock.withLock { () -> Result<ConfigFetchResult, Error> in
            asked.append(etag)
            return answers.isEmpty ? .success(.notModified) : answers.removeFirst()
        }
        return try next.get()
    }
}

/// Storage in memory.
public final class MemoryConfigStorage: ConfigStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: (set: Data?, etag: String?) = (nil, nil)

    public init(set: Data? = nil, etag: String? = nil) { values = (set, etag) }

    public var setData: Data? {
        get { lock.withLock { values.set } }
        set { lock.withLock { values.set = newValue } }
    }

    public var etag: String? {
        get { lock.withLock { values.etag } }
        set { lock.withLock { values.etag = newValue } }
    }
}

/// Keeps every event handed to `record`.
public final class RecordingConfigSink: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ConfigEvent] = []

    public init() {}

    public var events: [ConfigEvent] { lock.withLock { recorded } }

    public var record: @Sendable (ConfigEvent) -> Void {
        { event in self.lock.withLock { self.recorded.append(event) } }
    }
}
