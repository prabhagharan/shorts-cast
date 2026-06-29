// Tests/ShortsCastCaptureTests/CaptureGeometryTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCapture

final class CaptureGeometryTests: XCTestCase {
    func test_pixelSize_appliesScale() {
        let g = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2)
        XCTAssertEqual(g.pixelSize, CGSize(width: 1600, height: 1200))
    }
    func test_mainDisplay_mapsPointToPixels() {
        let g = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 2)
        XCTAssertEqual(g.mapToPixels(CGPoint(x: 100, y: 50)), CGPoint(x: 200, y: 100))
    }
    func test_offsetDisplay_subtractsOrigin() {
        // a 2x external display arranged to the right of a 1920-wide main display
        let g = CaptureGeometry(captureRect: CGRect(x: 1920, y: 0, width: 1000, height: 1000), scale: 2)
        XCTAssertEqual(g.mapToPixels(CGPoint(x: 1920 + 10, y: 5)), CGPoint(x: 20, y: 10))
    }
    func test_outOfBounds_returnsNil() {
        let g = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        XCTAssertNil(g.mapToPixels(CGPoint(x: -1, y: 5)))
        XCTAssertNil(g.mapToPixels(CGPoint(x: 5, y: 101)))
    }
}
