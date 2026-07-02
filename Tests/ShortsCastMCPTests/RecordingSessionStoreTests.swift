import XCTest
import ShortsCastCore
@testable import ShortsCastCapture
@testable import ShortsCastMCP

final class FakeSession: CaptureSessionProtocol {
    let result: Recorder.Result
    init(_ url: URL) {
        result = Recorder.Result(bundleURL: url,
                                 eventLog: EventLog(duration: 3, screenSize: .init(width: 100, height: 100), events: []))
    }
    func start() async throws {}
    func stop() async throws -> Recorder.Result { result }
}

final class RecordingSessionStoreTests: XCTestCase {
    private func active(_ store: RecordingSessionStore, _ id: String, _ url: URL) -> RecordingSessionStore.Active {
        .init(id: id, startedAt: Date(), targetDesc: "display", bundleURL: url, session: FakeSession(url))
    }

    func test_beginTwice_throwsBusy() async throws {
        let store = RecordingSessionStore()
        let url = URL(fileURLWithPath: "/tmp/a.shortscast")
        try await store.begin(active(store, "s1", url))
        do { try await store.begin(active(store, "s2", url)); XCTFail("expected busy") }
        catch { XCTAssertEqual(error as? RecordingSessionStore.StoreError, .busy) }
    }

    func test_endWithoutBegin_throwsIdle() async {
        let store = RecordingSessionStore()
        do { _ = try await store.end(); XCTFail("expected idle") }
        catch { XCTAssertEqual(error as? RecordingSessionStore.StoreError, .idle) }
    }

    func test_beginEnd_recordsEntry_andClears() async throws {
        let store = RecordingSessionStore()
        let url = URL(fileURLWithPath: "/tmp/b.shortscast")
        try await store.begin(active(store, "s1", url))
        let (entry, result) = try await store.end()
        XCTAssertEqual(result.bundleURL, url)
        XCTAssertEqual(entry.duration, 3)
        let none = await store.current()
        XCTAssertNil(none)
        let recent = await store.recent()
        XCTAssertEqual(recent.first?.bundleURL, url)
    }

    func test_entryForNilBundle_defaultsToMostRecent() async throws {
        let store = RecordingSessionStore()
        let u1 = URL(fileURLWithPath: "/tmp/1.shortscast")
        let u2 = URL(fileURLWithPath: "/tmp/2.shortscast")
        try await store.begin(active(store, "s1", u1)); _ = try await store.end()
        try await store.begin(active(store, "s2", u2)); _ = try await store.end()
        let e = try await store.entry(for: nil)
        XCTAssertEqual(e.bundleURL, u2)
    }
}
