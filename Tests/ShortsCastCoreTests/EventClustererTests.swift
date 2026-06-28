// Tests/ShortsCastCoreTests/EventClustererTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class EventClustererTests: XCTestCase {
    private func clusterer() -> EventClusterer { EventClusterer(settings: AutoDirectorSettings()) }

    func test_nearbyClicks_mergeIntoOneSegment() {
        let log = EventLog(duration: 10, screenSize: CGSize(width: 1920, height: 1080), events: [
            .click(t: 1.0, point: CGPoint(x: 100, y: 100), button: .left),
            .click(t: 1.3, point: CGPoint(x: 110, y: 105), button: .left),
            .click(t: 1.6, point: CGPoint(x: 90, y: 95), button: .left)
        ])
        let segs = clusterer().segments(from: log)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].start, 1.0, accuracy: 1e-6)
        XCTAssertEqual(segs[0].end, 1.6, accuracy: 1e-6)
        XCTAssertEqual(segs[0].center.x, 100, accuracy: 5) // ~centroid
    }

    func test_distantInTime_splitsIntoTwoSegments() {
        let log = EventLog(duration: 20, screenSize: CGSize(width: 1920, height: 1080), events: [
            .click(t: 1.0, point: CGPoint(x: 100, y: 100), button: .left),
            .click(t: 10.0, point: CGPoint(x: 100, y: 100), button: .left)
        ])
        XCTAssertEqual(clusterer().segments(from: log).count, 2)
    }

    func test_distantInSpace_splitsIntoTwoSegments() {
        let log = EventLog(duration: 10, screenSize: CGSize(width: 1920, height: 1080), events: [
            .click(t: 1.0, point: CGPoint(x: 100, y: 100), button: .left),
            .click(t: 1.2, point: CGPoint(x: 1800, y: 1000), button: .left)
        ])
        XCTAssertEqual(clusterer().segments(from: log).count, 2)
    }

    func test_cursorSamplesIgnored() {
        let log = EventLog(duration: 10, screenSize: CGSize(width: 1920, height: 1080), events: [
            .cursor(t: 0.5, point: CGPoint(x: 10, y: 10)),
            .cursor(t: 0.8, point: CGPoint(x: 20, y: 20))
        ])
        XCTAssertTrue(clusterer().segments(from: log).isEmpty)
    }

    func test_denseCluster_getsZoomBonus() {
        let s = AutoDirectorSettings()
        var events: [RecordingEvent] = []
        for i in 0..<6 { events.append(.click(t: 1.0 + Double(i) * 0.2,
                                               point: CGPoint(x: 100, y: 100), button: .left)) }
        let log = EventLog(duration: 10, screenSize: CGSize(width: 1920, height: 1080), events: events)
        let segs = EventClusterer(settings: s).segments(from: log)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].zoom, min(s.defaultZoom + s.denseZoomBonus, s.maxZoom), accuracy: 1e-6)
    }
}
