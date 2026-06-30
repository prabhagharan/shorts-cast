import XCTest
@testable import ShortsCastEditor

final class ScaffoldTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(ShortsCastEditor.version.isEmpty)
    }
}
