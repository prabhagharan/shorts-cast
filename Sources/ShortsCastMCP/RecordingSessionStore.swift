import Foundation
import ShortsCastCore
import ShortsCastCapture
import ShortsCastRender
import ShortsCastEditor

public actor RecordingSessionStore {
    public struct Active {
        public let id: String
        public let startedAt: Date
        public let targetDesc: String
        public let bundleURL: URL
        public let session: CaptureSessionProtocol
        public init(id: String, startedAt: Date, targetDesc: String,
                    bundleURL: URL, session: CaptureSessionProtocol) {
            self.id = id; self.startedAt = startedAt; self.targetDesc = targetDesc
            self.bundleURL = bundleURL; self.session = session
        }
    }
    public struct Entry {
        public let bundleURL: URL
        public let createdISO: String
        public var duration: Double
        public var segments: [FocusSegment]
        public var edits: ProjectEdits
    }
    public enum StoreError: Error, Equatable { case busy, idle, notFound }

    private var active: Active?
    private var entries: [Entry] = []   // append order; most-recent = last

    public init() {}

    public static func defaultEdits() -> ProjectEdits {
        ProjectEdits(overrides: [], style: .default,
                     formatName: OutputFormat.vertical9x16.name, settings: AutoDirectorSettings())
    }

    public func begin(_ a: Active) throws {
        guard active == nil else { throw StoreError.busy }
        active = a
    }

    public func end() async throws -> (Entry, Recorder.Result) {
        guard let a = active else { throw StoreError.idle }
        let result = try await a.session.stop()
        active = nil
        let entry = Entry(bundleURL: a.bundleURL,
                          createdISO: ISO8601DateFormatter().string(from: a.startedAt),
                          duration: result.eventLog.duration, segments: [],
                          edits: Self.defaultEdits())
        entries.append(entry)
        return (entry, result)
    }

    public func current() -> Active? { active }
    public func register(_ entry: Entry) { entries.append(entry) }
    public func recent() -> [Entry] { entries.reversed() }

    public func entry(for bundle: URL?) throws -> Entry {
        if let bundle {
            if let e = entries.last(where: { $0.bundleURL == bundle }) { return e }
            // Disk fallback: the MCP server is restarted routinely by clients, so a valid
            // on-disk bundle may not be in memory. Reconstruct + cache it so bundle-addressed
            // tools (export/list_segments/set_*/open_in_app) work across restarts.
            if let e = Self.reconstruct(bundle) { entries.append(e); return e }
            throw StoreError.notFound
        }
        guard let e = entries.last else { throw StoreError.notFound }
        return e
    }

    /// Rebuilds an Entry from a bundle on disk: the recorded EventLog + its persisted
    /// ProjectEdits, with segments re-derived under the persisted settings. Returns nil
    /// if `bundle` is not a readable `.shortscast` directory.
    public static func reconstruct(_ bundle: URL) -> Entry? {
        let events = bundle.appendingPathComponent("events.json")
        guard FileManager.default.fileExists(atPath: events.path),
              let read = try? ProjectBundle.read(bundle) else { return nil }
        let edits = EditsStore.read(bundle)
        let segments = Director(settings: edits.settings).direct(log: read.eventLog, overrides: []).segments
        return Entry(bundleURL: bundle, createdISO: read.meta.created,
                     duration: read.eventLog.duration, segments: segments, edits: edits)
    }

    public func update(bundle: URL, mutate: (inout Entry) -> Void) throws {
        guard let i = entries.lastIndex(where: { $0.bundleURL == bundle }) else { throw StoreError.notFound }
        mutate(&entries[i])
    }
}
