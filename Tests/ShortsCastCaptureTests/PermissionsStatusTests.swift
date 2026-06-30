import XCTest
@testable import ShortsCastCapture

final class PermissionsStatusTests: XCTestCase {
    func test_allGrantedHasNoMissingNames() {
        let s = Permissions.Status(screenRecording: true, accessibility: true, inputMonitoring: true)
        XCTAssertTrue(s.allGranted)
        XCTAssertTrue(s.missingNames.isEmpty)
    }
    func test_missingNamesListsEachUngrantedPermissionInOrder() {
        let s = Permissions.Status(screenRecording: false, accessibility: true, inputMonitoring: false)
        XCTAssertFalse(s.allGranted)
        XCTAssertEqual(s.missingNames, ["Screen Recording", "Input Monitoring"])
    }
    func test_missingNamesIncludesAllThreeWhenNoneGranted() {
        let s = Permissions.Status(screenRecording: false, accessibility: false, inputMonitoring: false)
        XCTAssertEqual(s.missingNames, ["Screen Recording", "Accessibility", "Input Monitoring"])
    }
}
