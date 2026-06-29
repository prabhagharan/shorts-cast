// Tests/ShortsCastRenderTests/ScaffoldTests.swift
import XCTest
@testable import ShortsCastRender

final class ScaffoldTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(ShortsCastRender.version.isEmpty)
    }
}
