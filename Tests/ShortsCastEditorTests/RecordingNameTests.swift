// Tests/ShortsCastEditorTests/RecordingNameTests.swift
import XCTest
@testable import ShortsCastEditor

final class RecordingNameTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func test_embedsTimestamp() {
        let d = Date(timeIntervalSince1970: 1_000_000_000) // 2001-09-09 01:46:40 UTC
        XCTAssertEqual(RecordingName.suggested(date: d, timeZone: utc),
                       "recording-2001-09-09-014640.shortscast")
    }

    func test_distinctTimesGiveDistinctNames() {
        let a = RecordingName.suggested(date: Date(timeIntervalSince1970: 1_000_000_000), timeZone: utc)
        let b = RecordingName.suggested(date: Date(timeIntervalSince1970: 1_000_000_001), timeZone: utc)
        XCTAssertNotEqual(a, b)
    }
}
