import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastCapture
@testable import ShortsCastMCP

final class HandlersLifecycleTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    private func makeHandlers(_ store: RecordingSessionStore) -> Handlers {
        Handlers(store: store, outputDir: URL(fileURLWithPath: NSTemporaryDirectory()),
                 requestPermissions: { }, permissionMissing: { [] },
                 resolveTarget: { _ in
                     ResolvedTarget(kind: "display", displayID: 0,
                                    captureRectPoints: CGRect(x: 0, y: 0, width: 100, height: 100),
                                    scale: 1, cropRect: nil)
                 },
                 makeSession: { _, url in FakeSession(url) })
    }

    func test_statusNone_thenStart_thenStatusActive_thenStop() async throws {
        let store = RecordingSessionStore()
        let h = makeHandlers(store)

        let s0 = await h.recordingStatus(nil)
        XCTAssertTrue(s0.text.contains("none"))

        let started = await h.startRecording(json("{}"))
        XCTAssertFalse(started.isError)
        XCTAssertTrue(started.text.contains("session"))

        let s1 = await h.recordingStatus(nil)
        XCTAssertTrue(s1.text.contains("display"))

        let stopped = await h.stopRecording(nil)
        XCTAssertFalse(stopped.isError)
        XCTAssertTrue(stopped.text.contains(".shortscast"))
    }

    func test_startWhileActive_isError() async throws {
        let store = RecordingSessionStore()
        let h = makeHandlers(store)
        _ = await h.startRecording(json("{}"))
        let again = await h.startRecording(json("{}"))
        XCTAssertTrue(again.isError)
        XCTAssertTrue(again.text.lowercased().contains("already"))
    }
}
