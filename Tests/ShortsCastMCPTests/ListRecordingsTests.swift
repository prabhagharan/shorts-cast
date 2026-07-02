import XCTest
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastMCP

final class ListRecordingsTests: XCTestCase {
    func test_listsMostRecentFirst() async throws {
        let store = RecordingSessionStore()
        let h = Handlers(store: store)
        for name in ["a", "b"] {
            let url = URL(fileURLWithPath: "/tmp/\(name).shortscast")
            await store.register(.init(bundleURL: url, createdISO: "2026-07-01T00:00:00Z",
                                       duration: 5, segments: [],
                                       edits: RecordingSessionStore.defaultEdits()))
        }
        let res = await h.listRecordings(nil)
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        let arr = v["recordings"]?.arrayValue
        XCTAssertEqual(arr?.count, 2)
        XCTAssertEqual(arr?.first?["bundle_path"]?.stringValue, "/tmp/b.shortscast")
    }
}
