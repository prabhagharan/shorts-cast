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
            guard let e = entries.last(where: { $0.bundleURL == bundle }) else { throw StoreError.notFound }
            return e
        }
        guard let e = entries.last else { throw StoreError.notFound }
        return e
    }

    public func update(bundle: URL, mutate: (inout Entry) -> Void) throws {
        guard let i = entries.lastIndex(where: { $0.bundleURL == bundle }) else { throw StoreError.notFound }
        mutate(&entries[i])
    }
}
