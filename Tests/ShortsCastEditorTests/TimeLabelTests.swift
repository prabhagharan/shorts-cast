// Tests/ShortsCastEditorTests/TimeLabelTests.swift
import XCTest
@testable import ShortsCastEditor

final class TimeLabelTests: XCTestCase {
    func test_formatsMinutesSeconds() {
        XCTAssertEqual(TimeLabel.format(0), "0:00")
        XCTAssertEqual(TimeLabel.format(3), "0:03")
        XCTAssertEqual(TimeLabel.format(63.4), "1:03")
        XCTAssertEqual(TimeLabel.format(125), "2:05")
    }
    func test_negativeClampsToZero() {
        XCTAssertEqual(TimeLabel.format(-5), "0:00")
    }
}
