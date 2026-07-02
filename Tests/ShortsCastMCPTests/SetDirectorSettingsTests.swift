import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastMCP

final class SetDirectorSettingsTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    /// Writes a bundle with a few click events so the director produces segments.
    private func makeBundle() throws -> URL {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sds-\(UUID().uuidString).shortscast")
        let log = EventLog(duration: 10, screenSize: .init(width: 400, height: 400), events: [
            .click(t: 1, point: CGPoint(x: 50, y: 50), button: .left),
            .click(t: 6, point: CGPoint(x: 350, y: 350), button: .left)
        ])
        let mov = bundle.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: mov.path, contents: Data([0, 1, 2]))
        defer { try? FileManager.default.removeItem(at: mov) }
        let meta = BundleMeta(targetKind: "display", displayID: 0, scale: 1,
                              captureRect: CGRect(x: 0, y: 0, width: 400, height: 400),
                              appVersion: "test", created: "2026-07-01T00:00:00Z")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: mov, to: bundle)
        return bundle
    }

    func test_safeField_reportsUnchangedSegments() async throws {
        let bundle = try makeBundle(); defer { try? FileManager.default.removeItem(at: bundle) }
        let store = RecordingSessionStore()
        await store.register(.init(bundleURL: bundle, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 10, segments: [], edits: RecordingSessionStore.defaultEdits()))
        let h = Handlers(store: store)
        let res = await h.setDirectorSettings(json(#"{"defaultZoom":3.0}"#))
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        XCTAssertEqual(v["segments_changed"]?.boolValue, false)
        XCTAssertEqual(EditsStore.read(bundle).settings.defaultZoom, 3.0)
    }

    func test_resegmentingField_returnsFreshSegments() async throws {
        let bundle = try makeBundle(); defer { try? FileManager.default.removeItem(at: bundle) }
        let store = RecordingSessionStore()
        await store.register(.init(bundleURL: bundle, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 10, segments: [], edits: RecordingSessionStore.defaultEdits()))
        let h = Handlers(store: store)
        let res = await h.setDirectorSettings(json(#"{"clusterTimeGap":0.1}"#))
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        XCTAssertEqual(v["segments_changed"]?.boolValue, true)
        XCTAssertNotNil(v["segments"]?.arrayValue)
        XCTAssertNotNil(v["old_segment_count"]?.intValue)
        XCTAssertNotNil(v["new_segment_count"]?.intValue)
    }
}
