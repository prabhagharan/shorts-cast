// Tests/ShortsCastCoreTests/CameraPathTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class CameraPathTests: XCTestCase {
    private func path() -> CameraPath {
        CameraPath(keyframes: [
            CameraKeyframe(t: 0, center: CGPoint(x: 0, y: 0), scale: 1),
            CameraKeyframe(t: 2, center: CGPoint(x: 100, y: 0), scale: 2)
        ])
    }
    func test_sample_clampsBeforeStartAndAfterEnd() {
        XCTAssertEqual(path().sample(at: -1).scale, 1, accuracy: 1e-6)
        XCTAssertEqual(path().sample(at: 99).scale, 2, accuracy: 1e-6)
    }
    func test_sample_midpoint_usesSmootherstepEasing() {
        // smootherstep(0.5) == 0.5, so midpoint is exactly halfway
        let s = path().sample(at: 1)
        XCTAssertEqual(s.center.x, 50, accuracy: 1e-6)
        XCTAssertEqual(s.scale, 1.5, accuracy: 1e-6)
    }
    func test_sample_quarter_isEasedNotLinear() {
        // at t=0.5 (u=0.25) easing < linear, so center.x < 25
        let s = path().sample(at: 0.5)
        XCTAssertLessThan(s.center.x, 25)
    }
}
