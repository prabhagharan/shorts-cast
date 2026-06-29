// Tests/ShortsCastRenderTests/FrameLayoutTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastRender

final class FrameLayoutTests: XCTestCase {
    func test_contentRect_centeredInset() {
        let r = FrameLayout.contentRect(exportSize: CGSize(width: 1080, height: 1920), paddingFraction: 0.05)
        XCTAssertEqual(r.width, 1080 * 0.9, accuracy: 1e-6)   // 972
        XCTAssertEqual(r.height, 1920 * 0.9, accuracy: 1e-6)  // 1728
        XCTAssertEqual(r.midX, 540, accuracy: 1e-6)
        XCTAssertEqual(r.midY, 960, accuracy: 1e-6)
    }
    func test_contentRect_zeroPaddingIsFullFrame() {
        let r = FrameLayout.contentRect(exportSize: CGSize(width: 800, height: 800), paddingFraction: 0)
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 800, height: 800))
    }
    func test_contentRect_clampsExcessivePadding() {
        let r = FrameLayout.contentRect(exportSize: CGSize(width: 1000, height: 1000), paddingFraction: 0.9)
        // clamped to 0.49 -> scale 0.02 -> 20x20, still centered and positive
        XCTAssertGreaterThan(r.width, 0)
        XCTAssertEqual(r.midX, 500, accuracy: 1e-6)
    }
}
