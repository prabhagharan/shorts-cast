import XCTest
@testable import ShortsCastCapture

final class PermissionsTests: XCTestCase {
    func test_allGranted_trueOnlyWhenAllThree() {
        XCTAssertTrue(Permissions.Status(screenRecording: true, accessibility: true, inputMonitoring: true).allGranted)
        XCTAssertFalse(Permissions.Status(screenRecording: false, accessibility: true, inputMonitoring: true).allGranted)
        XCTAssertFalse(Permissions.Status(screenRecording: true, accessibility: false, inputMonitoring: true).allGranted)
        XCTAssertFalse(Permissions.Status(screenRecording: true, accessibility: true, inputMonitoring: false).allGranted)
    }
}
