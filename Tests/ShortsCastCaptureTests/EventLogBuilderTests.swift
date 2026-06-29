// Tests/ShortsCastCaptureTests/EventLogBuilderTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastCapture

final class EventLogBuilderTests: XCTestCase {
    private let geo = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 1)

    func test_cursorThrottle_keepsLatestPerTick() {
        let b = EventLogBuilder(geometry: geo, cursorHz: 60) // interval ~0.01667s
        b.add(RawInputEvent(t: 0.000, kind: .cursorMove, globalPoint: CGPoint(x: 1, y: 1)))   // kept (first)
        b.add(RawInputEvent(t: 0.005, kind: .cursorMove, globalPoint: CGPoint(x: 2, y: 2)))   // dropped (<16.7ms)
        b.add(RawInputEvent(t: 0.020, kind: .cursorMove, globalPoint: CGPoint(x: 3, y: 3)))   // kept
        let log = b.build(firstFrameT: 0, endT: 1)
        XCTAssertEqual(log.events.filter { $0.type == .cursor }.count, 2)
    }

    func test_build_rebasesAndDropsPreStartEvents() {
        let b = EventLogBuilder(geometry: geo, cursorHz: 60)
        b.add(RawInputEvent(t: 1.0, kind: .mouseDown, globalPoint: CGPoint(x: 10, y: 10), button: .left)) // before frame
        b.add(RawInputEvent(t: 3.0, kind: .mouseDown, globalPoint: CGPoint(x: 20, y: 20), button: .left)) // after
        let log = b.build(firstFrameT: 2.0, endT: 5.0)
        XCTAssertEqual(log.events.count, 1)
        XCTAssertEqual(log.events[0].t, 1.0, accuracy: 1e-9) // 3.0 - 2.0
        XCTAssertEqual(log.duration, 3.0, accuracy: 1e-9)
        XCTAssertEqual(log.screenSize, CGSize(width: 1000, height: 1000))
    }

    func test_build_keysAreKeptAndSorted() {
        let b = EventLogBuilder(geometry: geo, cursorHz: 60)
        b.add(RawInputEvent(t: 2.5, kind: .key))
        b.add(RawInputEvent(t: 2.1, kind: .mouseDown, globalPoint: CGPoint(x: 5, y: 5), button: .left))
        let log = b.build(firstFrameT: 2.0, endT: 4.0)
        XCTAssertEqual(log.events.map { $0.type }, [.click, .key]) // sorted by t: 0.1 then 0.5
    }
}
