// Tests/ShortsCastCoreTests/DirectorTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class DirectorTests: XCTestCase {
    private let screen = CGSize(width: 1920, height: 1080)

    private func sampleLog() -> EventLog {
        EventLog(duration: 6, screenSize: screen, events: [
            .cursor(t: 0.0, point: CGPoint(x: 100, y: 100)),
            .click(t: 2.0, point: CGPoint(x: 400, y: 300), button: .left),
            .click(t: 2.3, point: CGPoint(x: 410, y: 305), button: .left),
            .cursor(t: 2.4, point: CGPoint(x: 410, y: 305))
        ])
    }

    func test_direct_producesSegmentsPathAndCursor() {
        let result = Director(settings: AutoDirectorSettings()).direct(log: sampleLog(), overrides: [])
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertFalse(result.cameraPath.keyframes.isEmpty)
        XCTAssertEqual(result.cursor.clicks.count, 2)
    }

    func test_override_changesGeneratedZoom() {
        let d = Director(settings: AutoDirectorSettings())
        let base = d.direct(log: sampleLog(), overrides: [])
        let overridden = d.direct(log: sampleLog(),
                                  overrides: [SegmentOverride(index: 0, zoom: 3.7, center: nil)])
        XCTAssertEqual(overridden.segments[0].zoom, 3.7, accuracy: 1e-6)
        XCTAssertNotEqual(base.segments[0].zoom, overridden.segments[0].zoom)
    }

    func test_cropRect_atActiveTime_isZoomedRect() {
        let d = Director(settings: AutoDirectorSettings())
        let result = d.direct(log: sampleLog(), overrides: [])
        let rect = d.cropRect(result, at: 2.3, format: .vertical9x16, screen: screen)
        // While zoomed, crop is narrower than the resting vertical crop (607.5).
        XCTAssertLessThan(rect.width, 607.5)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertLessThanOrEqual(rect.maxX, screen.width + 1e-6)
    }

    func test_direct_includesDwellSegmentWhenCursorLingersWithoutClicks() {
        var events: [RecordingEvent] = []
        var t = 0.0
        for _ in 0..<45 { events.append(.cursor(t: t, point: CGPoint(x: 700, y: 600))); t += 1.0/30.0 }
        let log = EventLog(duration: 3, screenSize: screen, events: events)
        let result = Director(settings: AutoDirectorSettings()).direct(log: log, overrides: [])
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].zoom, AutoDirectorSettings().dwellZoom, accuracy: 1e-6)
    }
}
