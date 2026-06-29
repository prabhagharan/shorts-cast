// Tests/ShortsCastRenderTests/RenderStyleTests.swift
import XCTest
import CoreImage
@testable import ShortsCastRender

final class RenderStyleTests: XCTestCase {
    func test_default_hasSaneValues() {
        let s = RenderStyle.default
        XCTAssertGreaterThan(s.paddingFraction, 0)
        XCTAssertLessThan(s.paddingFraction, 0.49)
        XCTAssertGreaterThan(s.cornerRadius, 0)
        XCTAssertGreaterThan(s.rippleDuration, 0)
    }
    func test_jsonRoundTrip_preservesStyleAndBackgroundCase() throws {
        let s = RenderStyle(
            background: .gradient(top: RGBA(0.1, 0.2, 0.3, 1), bottom: RGBA(0, 0, 0, 1)),
            cornerRadius: 20, shadowOpacity: 0.4, shadowBlur: 18, shadowOffsetY: 10,
            paddingFraction: 0.05, cursorRadius: 16, cursorColor: RGBA(1, 1, 1, 1),
            rippleDuration: 0.5, rippleMaxRadius: 40)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(RenderStyle.self, from: data)
        XCTAssertEqual(decoded, s)
    }
    func test_rgba_toCIColorComponents() {
        let c = RGBA(0.25, 0.5, 0.75, 1).ciColor
        XCTAssertEqual(Double(c.red), 0.25, accuracy: 1e-6)
        XCTAssertEqual(Double(c.green), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(c.blue), 0.75, accuracy: 1e-6)
    }
}
