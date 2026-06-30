// Tests/ShortsCastEditorTests/TimelineLayoutTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastEditor

final class TimelineLayoutTests: XCTestCase {
    private func seg(_ s: Double, _ e: Double) -> FocusSegment {
        FocusSegment(start: s, end: e, center: .zero, zoom: 2)
    }
    func test_mapsTimeRangesToRects() {
        let rects = TimelineLayout.xPositions(segments: [seg(0, 2), seg(5, 10)],
                                              duration: 10, width: 100, height: 20)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].minX, 0, accuracy: 1e-6)
        XCTAssertEqual(rects[0].width, 20, accuracy: 1e-6)   // (2-0)/10*100
        XCTAssertEqual(rects[1].minX, 50, accuracy: 1e-6)    // 5/10*100
        XCTAssertEqual(rects[1].width, 50, accuracy: 1e-6)   // (10-5)/10*100
        XCTAssertEqual(rects[0].height, 20, accuracy: 1e-6)
    }
    func test_clampsToWidth() {
        let rects = TimelineLayout.xPositions(segments: [seg(8, 20)], duration: 10, width: 100, height: 10)
        XCTAssertGreaterThanOrEqual(rects[0].minX, 0)
        XCTAssertLessThanOrEqual(rects[0].maxX, 100 + 1e-6) // clamped even though end>duration
    }
    func test_zeroDurationReturnsEmpty() {
        XCTAssertTrue(TimelineLayout.xPositions(segments: [seg(0, 1)], duration: 0, width: 100, height: 10).isEmpty)
    }
}
