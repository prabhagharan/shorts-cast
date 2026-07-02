import XCTest
import ShortsCastCapture
@testable import ShortsCastMCP

final class OpenInAppTests: XCTestCase {
    func test_open_invokesLauncherWithBundle() async throws {
        let bundle = URL(fileURLWithPath: "/tmp/open-\(UUID().uuidString).shortscast")
        let store = RecordingSessionStore()
        await store.register(.init(bundleURL: bundle, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 1, segments: [], edits: RecordingSessionStore.defaultEdits()))
        var opened: URL?
        let h = Handlers(store: store, launch: { url in opened = url; return true })
        let res = await h.openInApp(nil)
        XCTAssertFalse(res.isError)
        XCTAssertEqual(opened, bundle)
    }
}
