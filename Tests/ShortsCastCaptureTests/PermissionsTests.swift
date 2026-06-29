import XCTest
@testable import ShortsCastCapture

final class PermissionsTests: XCTestCase {
    func test_allGranted_trueOnlyWhenBoth() {
        XCTAssertTrue(Permissions.Status(screenRecording: true, accessibility: true).allGranted)
        XCTAssertFalse(Permissions.Status(screenRecording: true, accessibility: false).allGranted)
        XCTAssertFalse(Permissions.Status(screenRecording: false, accessibility: true).allGranted)
    }
}
