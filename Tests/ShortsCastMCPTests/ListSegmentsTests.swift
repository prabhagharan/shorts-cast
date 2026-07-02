import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastMCP

final class ListSegmentsTests: XCTestCase {
    func test_listsSegmentsWithSummaries() async throws {
        // Write a real bundle so ProjectBundle.read works.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seg-\(UUID().uuidString).shortscast")
        let log = EventLog(duration: 4, screenSize: .init(width: 200, height: 200), events: [
            .click(t: 0.5, point: .zero, button: .left)
        ])
        let mov = tmp.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: mov.path, contents: Data([0, 1, 2]))
        defer { try? FileManager.default.removeItem(at: mov) }
        let meta = BundleMeta(targetKind: "display", displayID: 0, scale: 1,
                              captureRect: CGRect(x: 0, y: 0, width: 200, height: 200),
                              appVersion: "test", created: "2026-07-01T00:00:00Z")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: mov, to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = RecordingSessionStore()
        let seg = FocusSegment(start: 0, end: 1, center: CGPoint(x: 50, y: 60), zoom: 2.5)
        await store.register(.init(bundleURL: tmp, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 4, segments: [seg], edits: RecordingSessionStore.defaultEdits()))
        let h = Handlers(store: store)
        let res = await h.listSegments(nil)
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        let s0 = v["segments"]?.arrayValue?.first
        XCTAssertEqual(s0?["index"]?.intValue, 0)
        XCTAssertEqual(s0?["zoom"]?.doubleValue, 2.5)
        XCTAssertEqual(s0?["center"]?["x"]?.doubleValue, 50)
        XCTAssertEqual(s0?["summary"]?.stringValue, "1 click (1 left)")
    }
}
