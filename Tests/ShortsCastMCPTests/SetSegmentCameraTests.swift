import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastMCP

final class SetSegmentCameraTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    func test_setsZoomAndPersists() async throws {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ssc-\(UUID().uuidString).shortscast")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }

        let store = RecordingSessionStore()
        let seg = FocusSegment(start: 0, end: 1, center: .zero, zoom: 2)
        await store.register(.init(bundleURL: bundle, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 2, segments: [seg], edits: RecordingSessionStore.defaultEdits()))
        let h = Handlers(store: store)

        let res = await h.setSegmentCamera(json(#"{"index":0,"zoom":2.8}"#))
        XCTAssertFalse(res.isError)
        // Persisted to project.json
        XCTAssertEqual(EditsStore.read(bundle).overrides.first?.zoom, 2.8)
        // Cached in the entry
        let e = try await store.entry(for: bundle)
        XCTAssertEqual(e.edits.overrides.first?.index, 0)
    }
}
