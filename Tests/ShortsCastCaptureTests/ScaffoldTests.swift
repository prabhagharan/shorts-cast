// Tests/ShortsCastCaptureTests/ScaffoldTests.swift
import XCTest
@testable import ShortsCastCapture

final class ScaffoldTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(ShortsCastCapture.version.isEmpty)
    }
}
