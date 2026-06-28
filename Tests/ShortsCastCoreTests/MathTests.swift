// Tests/ShortsCastCoreTests/MathTests.swift
import XCTest
@testable import ShortsCastCore

final class MathTests: XCTestCase {
    func test_lerp_midpoint() {
        XCTAssertEqual(lerp(0, 10, 0.5), 5, accuracy: 1e-9)
    }
    func test_smootherstep_endpointsAndMid() {
        XCTAssertEqual(smootherstep(0), 0, accuracy: 1e-9)
        XCTAssertEqual(smootherstep(1), 1, accuracy: 1e-9)
        XCTAssertEqual(smootherstep(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(smootherstep(-2), 0, accuracy: 1e-9) // clamps
    }
    func test_clamp() {
        XCTAssertEqual(clampD(5, 0, 3), 3, accuracy: 1e-9)
        XCTAssertEqual(clampD(-1, 0, 3), 0, accuracy: 1e-9)
    }
}
