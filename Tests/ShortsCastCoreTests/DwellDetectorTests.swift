// Tests/ShortsCastCoreTests/DwellDetectorTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class DwellDetectorTests: XCTestCase {
    private let screen = CGSize(width: 1920, height: 1080)
    private func detector() -> DwellDetector { DwellDetector(settings: AutoDirectorSettings()) }

    func test_lingeringCursor_producesGentleZoomSegment() {
        var events: [RecordingEvent] = []
        var t = 0.0
        for _ in 0..<45 { events.append(.cursor(t: t, point: CGPoint(x: 500, y: 500))); t += 1.0/30.0 }
        let log = EventLog(duration: 3, screenSize: screen, events: events)
        let segs = detector().segments(from: log)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].zoom, AutoDirectorSettings().dwellZoom, accuracy: 1e-6)
        XCTAssertEqual(segs[0].center.x, 500, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(segs[0].end - segs[0].start, AutoDirectorSettings().dwellTime)
    }

    func test_movingCursor_producesNoSegment() {
        var events: [RecordingEvent] = []
        var t = 0.0
        var x = 0.0
        for _ in 0..<45 { events.append(.cursor(t: t, point: CGPoint(x: x, y: 0))); t += 1.0/30.0; x += 100 }
        let log = EventLog(duration: 3, screenSize: screen, events: events)
        XCTAssertTrue(detector().segments(from: log).isEmpty)
    }

    func test_briefPause_belowThreshold_producesNoSegment() {
        var events: [RecordingEvent] = []
        var t = 0.0
        for _ in 0..<15 { events.append(.cursor(t: t, point: CGPoint(x: 500, y: 500))); t += 1.0/30.0 } // ~0.47s
        events.append(.cursor(t: t + 0.1, point: CGPoint(x: 1500, y: 900)))                              // jump away
        let log = EventLog(duration: 3, screenSize: screen, events: events)
        XCTAssertTrue(detector().segments(from: log).isEmpty)
    }
}
