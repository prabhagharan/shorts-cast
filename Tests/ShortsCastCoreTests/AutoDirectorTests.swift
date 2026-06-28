// Tests/ShortsCastCoreTests/AutoDirectorTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class AutoDirectorTests: XCTestCase {
    private let screen = CGSize(width: 1920, height: 1080)

    func test_singleSegment_zoomsInThenBackToResting() {
        let s = AutoDirectorSettings()
        let seg = FocusSegment(start: 2.0, end: 2.5, center: CGPoint(x: 400, y: 300), zoom: 2.5)
        let path = AutoDirector(settings: s).cameraPath(segments: [seg], duration: 10, screenSize: screen)

        // Resting at the very start.
        XCTAssertEqual(path.sample(at: 0).scale, s.restingZoom, accuracy: 1e-6)
        XCTAssertEqual(path.sample(at: 0).center.x, screen.width / 2, accuracy: 1e-6)

        // Fully zoomed while the segment is active.
        let mid = path.sample(at: 2.5)
        XCTAssertEqual(mid.scale, 2.5, accuracy: 1e-6)
        XCTAssertEqual(mid.center.x, 400, accuracy: 1e-6)

        // Back to resting well after inactivity timeout + zoom-out.
        let after = path.sample(at: 2.5 + s.inactivityTimeout + s.zoomOutDuration + 0.5)
        XCTAssertEqual(after.scale, s.restingZoom, accuracy: 1e-6)
    }

    func test_keyframeTimes_areStrictlyIncreasing() {
        let s = AutoDirectorSettings()
        // Two segments close enough to stay zoomed between them.
        let segs = [
            FocusSegment(start: 1.0, end: 1.2, center: CGPoint(x: 200, y: 200), zoom: 2.5),
            FocusSegment(start: 1.4, end: 1.6, center: CGPoint(x: 800, y: 400), zoom: 2.5)
        ]
        let path = AutoDirector(settings: s).cameraPath(segments: segs, duration: 5, screenSize: screen)
        for i in 1..<path.keyframes.count {
            XCTAssertGreaterThan(path.keyframes[i].t, path.keyframes[i-1].t)
        }
    }

    func test_emptySegments_staysRestingForWholeDuration() {
        let path = AutoDirector(settings: AutoDirectorSettings())
            .cameraPath(segments: [], duration: 8, screenSize: screen)
        XCTAssertEqual(path.sample(at: 4).scale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(path.sample(at: 8).center.x, screen.width / 2, accuracy: 1e-6)
    }
}
