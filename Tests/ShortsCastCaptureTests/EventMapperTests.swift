// Tests/ShortsCastCaptureTests/EventMapperTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastCapture

final class EventMapperTests: XCTestCase {
    private let geo = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 2)

    func test_mouseDown_mapsToClickInPixels() {
        let raw = RawInputEvent(t: 1.5, kind: .mouseDown, globalPoint: CGPoint(x: 100, y: 50), button: .left)
        let e = EventMapper.map(raw, geometry: geo)
        XCTAssertEqual(e?.type, .click)
        XCTAssertEqual(e?.point, CGPoint(x: 200, y: 100))
        XCTAssertEqual(e?.button, .left)
        XCTAssertEqual(e?.t ?? -1, 1.5, accuracy: 1e-9)
    }
    func test_key_keptWithNoPoint() {
        let e = EventMapper.map(RawInputEvent(t: 2.0, kind: .key), geometry: geo)
        XCTAssertEqual(e?.type, .key)
        XCTAssertNil(e?.point)
    }
    func test_scroll_preservesDeltaSign() {
        let raw = RawInputEvent(t: 3.0, kind: .scroll, globalPoint: CGPoint(x: 10, y: 10), scrollDeltaY: -4)
        let e = EventMapper.map(raw, geometry: geo)
        XCTAssertEqual(e?.type, .scroll)
        XCTAssertEqual(e?.deltaY ?? 0, -4, accuracy: 1e-9)
    }
    func test_outOfBoundsClick_returnsNil() {
        let raw = RawInputEvent(t: 1, kind: .mouseDown, globalPoint: CGPoint(x: 5000, y: 5000), button: .left)
        XCTAssertNil(EventMapper.map(raw, geometry: geo))
    }
    func test_mouseDownWithoutButton_returnsNil() {
        let raw = RawInputEvent(t: 1, kind: .mouseDown, globalPoint: CGPoint(x: 10, y: 10), button: nil)
        XCTAssertNil(EventMapper.map(raw, geometry: geo))
    }
}
