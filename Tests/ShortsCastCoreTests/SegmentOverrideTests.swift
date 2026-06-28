// Tests/ShortsCastCoreTests/SegmentOverrideTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class SegmentOverrideTests: XCTestCase {
    private func segs() -> [FocusSegment] {
        [FocusSegment(start: 0, end: 1, center: CGPoint(x: 10, y: 10), zoom: 2.5),
         FocusSegment(start: 2, end: 3, center: CGPoint(x: 20, y: 20), zoom: 2.5)]
    }
    func test_zoomOverride_appliesToCorrectSegment() {
        let out = applyOverrides(segs(), [SegmentOverride(index: 1, zoom: 3.2, center: nil)])
        XCTAssertEqual(out[0].zoom, 2.5, accuracy: 1e-6)
        XCTAssertEqual(out[1].zoom, 3.2, accuracy: 1e-6)
    }
    func test_centerOverride_applies() {
        let out = applyOverrides(segs(), [SegmentOverride(index: 0, zoom: nil, center: CGPoint(x: 99, y: 88))])
        XCTAssertEqual(out[0].center, CGPoint(x: 99, y: 88))
    }
    func test_outOfRangeIndex_ignored() {
        let out = applyOverrides(segs(), [SegmentOverride(index: 9, zoom: 3, center: nil)])
        XCTAssertEqual(out, segs())
    }
}
