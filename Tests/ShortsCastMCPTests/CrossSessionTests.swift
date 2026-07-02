import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastMCP

/// Exercises the "server restarted" case: a fresh, empty store addressing a bundle that
/// only exists on disk. Simulated by writing a real bundle and using a brand-new store.
final class CrossSessionTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    /// Writes a real .shortscast bundle (events/meta/raw) into `dir` with the given name.
    @discardableResult
    private func writeBundle(_ name: String, in dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = dir.appendingPathComponent("\(name).shortscast")
        let log = EventLog(duration: 7, screenSize: .init(width: 300, height: 300), events: [
            .click(t: 1, point: CGPoint(x: 40, y: 40), button: .left)
        ])
        let mov = dir.appendingPathComponent("\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: mov.path, contents: Data([0, 1, 2]))
        defer { try? FileManager.default.removeItem(at: mov) }
        let meta = BundleMeta(targetKind: "display", displayID: 0, scale: 1,
                              captureRect: CGRect(x: 0, y: 0, width: 300, height: 300),
                              appVersion: "test", created: "2026-01-02T03:04:05Z")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: mov, to: bundle)
        return bundle
    }

    func test_entryFor_reconstructsFromDisk_whenNotInStore() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("xs-\(UUID().uuidString)")
        let bundle = try writeBundle("rec", in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = RecordingSessionStore() // fresh — never saw this recording
        let e = try await store.entry(for: bundle)
        XCTAssertEqual(e.bundleURL, bundle)
        XCTAssertEqual(e.duration, 7)
        XCTAssertEqual(e.createdISO, "2026-01-02T03:04:05Z")
        XCTAssertFalse(e.segments.isEmpty) // a click → at least one focus segment
    }

    func test_export_worksForOnDiskBundle_afterRestart() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("xs-\(UUID().uuidString)")
        let bundle = try writeBundle("rec", in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Persist a non-default setting so we can confirm export loads from project.json.
        var edits = RecordingSessionStore.defaultEdits(); edits.settings.defaultZoom = 3.5
        try EditsStore.write(edits, to: bundle)

        let store = RecordingSessionStore()
        var captured: AutoDirectorSettings?
        let h = Handlers(store: store, outputDir: dir,
                         export: { _, _, _, settings, _, _ in captured = settings; return [dir.appendingPathComponent("out.mp4")] })
        let res = await h.exportRecording(json(#"{"bundle":"\#(bundle.path)"}"#))
        XCTAssertFalse(res.isError)
        XCTAssertEqual(captured?.defaultZoom, 3.5)
    }

    func test_listRecordings_includesOnDiskBundle_withEmptyStore() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("xs-\(UUID().uuidString)")
        let bundle = try writeBundle("2026-01-02_030405", in: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = RecordingSessionStore()
        let h = Handlers(store: store, outputDir: dir)
        let res = await h.listRecordings(nil)
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        let paths = v["recordings"]?.arrayValue?.compactMap { $0["bundle_path"]?.stringValue } ?? []
        // contentsOfDirectory resolves /var → /private/var, so match by bundle name.
        XCTAssertTrue(paths.contains { $0.hasSuffix("2026-01-02_030405.shortscast") },
                      "expected the on-disk bundle in \(paths)")
    }

    func test_setSegmentCamera_rejectsOutOfRangeIndex() async throws {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("oor-\(UUID().uuidString).shortscast")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let store = RecordingSessionStore()
        let seg = FocusSegment(start: 0, end: 1, center: .zero, zoom: 2)
        await store.register(.init(bundleURL: bundle, createdISO: "2026-01-01T00:00:00Z",
                                   duration: 2, segments: [seg], edits: RecordingSessionStore.defaultEdits()))
        let h = Handlers(store: store)
        let res = await h.setSegmentCamera(json(#"{"index":5,"zoom":2.8}"#))
        XCTAssertTrue(res.isError)
        XCTAssertTrue(res.text.lowercased().contains("out of range"))
    }
}
