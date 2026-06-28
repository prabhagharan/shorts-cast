// Tests/ShortsCastCoreTests/ScaffoldTests.swift
import XCTest
@testable import ShortsCastCore

final class ScaffoldTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(ShortsCastCore.version.isEmpty)
    }
}
