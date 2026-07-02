import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastMCP

final class SegmentSummaryTests: XCTestCase {
    func test_countsWithinWindow_excludingCursor() {
        let log = EventLog(duration: 10, screenSize: .init(width: 100, height: 100), events: [
            .click(t: 1.0, point: .zero, button: .left),
            .click(t: 1.2, point: .zero, button: .left),
            .click(t: 1.4, point: .zero, button: .right),
            .key(t: 1.5), .key(t: 1.6),
            .scroll(t: 1.7, point: .zero, deltaY: 3),
            .cursor(t: 1.8, point: .zero),           // excluded
            .click(t: 5.0, point: .zero, button: .left) // outside window
        ])
        let seg = FocusSegment(start: 0.5, end: 2.0, center: .zero, zoom: 2)
        let s = SegmentSummary.describe(segment: seg, in: log)
        XCTAssertEqual(s, "3 clicks (2 left, 1 right), 2 keystrokes, 1 scroll")
    }

    func test_emptyWindow_saysNoInput() {
        let log = EventLog(duration: 10, screenSize: .init(width: 100, height: 100), events: [])
        let seg = FocusSegment(start: 0, end: 1, center: .zero, zoom: 2)
        XCTAssertEqual(SegmentSummary.describe(segment: seg, in: log), "no input")
    }
}
