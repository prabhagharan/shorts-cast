import XCTest
@testable import ShortsCastMCP

final class SessionPathsTests: XCTestCase {
    func test_timestamp_isFilesystemSafe_andStable() {
        let d = Date(timeIntervalSince1970: 1_700_000_000) // fixed instant
        let ts = SessionPaths.timestamp(d)
        XCTAssertFalse(ts.contains(":"))
        XCTAssertFalse(ts.contains(" "))
        XCTAssertEqual(ts, SessionPaths.timestamp(d)) // deterministic
    }

    func test_bundleURL_hasShortscastExtension_inGivenDir() {
        let dir = URL(fileURLWithPath: "/tmp/out")
        let url = SessionPaths.bundleURL(at: Date(timeIntervalSince1970: 1_700_000_000), dir: dir)
        XCTAssertEqual(url.pathExtension, "shortscast")
        XCTAssertEqual(url.deletingLastPathComponent().path, "/tmp/out")
    }
}
