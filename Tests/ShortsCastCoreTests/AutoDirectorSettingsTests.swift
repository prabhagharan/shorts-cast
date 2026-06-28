// Tests/ShortsCastCoreTests/AutoDirectorSettingsTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class AutoDirectorSettingsTests: XCTestCase {
    func test_defaults() {
        let s = AutoDirectorSettings()
        XCTAssertEqual(s.defaultZoom, 2.5, accuracy: 1e-6)
        XCTAssertEqual(s.maxZoom, 4.0, accuracy: 1e-6)
        XCTAssertEqual(s.clusterTimeGap, 1.5, accuracy: 1e-6)
    }
    func test_focusSegment_isMutable() {
        var seg = FocusSegment(start: 0, end: 1, center: .zero, zoom: 2)
        seg.zoom = 3
        XCTAssertEqual(seg.zoom, 3, accuracy: 1e-6)
    }
}
