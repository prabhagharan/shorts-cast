import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastEditor
@testable import ShortsCastMCP

final class EditsStoreTests: XCTestCase {
    func test_write_thenRead_roundTrips() throws {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edits-\(UUID().uuidString).shortscast")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }

        var edits = RecordingSessionStore.defaultEdits()
        edits.overrides = [SegmentOverride(index: 2, zoom: 3.0)]
        try EditsStore.write(edits, to: bundle)

        let back = EditsStore.read(bundle)
        XCTAssertEqual(back.overrides.first?.index, 2)
        XCTAssertEqual(back.overrides.first?.zoom, 3.0)
    }

    func test_read_missing_returnsDefaults() {
        let bundle = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).shortscast")
        XCTAssertEqual(EditsStore.read(bundle).overrides.count, 0)
    }
}
