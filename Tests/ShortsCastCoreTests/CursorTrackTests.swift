import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class CursorTrackTests: XCTestCase {
    func test_build_smoothsCursorAndCollectsClicks() {
        var events: [RecordingEvent] = []
        var t = 0.0
        events.append(.cursor(t: t, point: .zero))
        for _ in 0..<60 { t += 1.0/60.0; events.append(.cursor(t: t, point: CGPoint(x: 200, y: 0))) }
        events.append(.click(t: 0.5, point: CGPoint(x: 200, y: 0), button: .left))
        let log = EventLog(duration: 2, screenSize: CGSize(width: 1920, height: 1080), events: events)

        let track = CursorTrackBuilder(smoother: SpringSmoother(frequency: 6)).build(from: log)

        XCTAssertEqual(track.samples.count, 61)              // one per cursor sample
        XCTAssertEqual(track.samples.first!.p, .zero)        // first preserved
        XCTAssertGreaterThan(Double(track.samples.last!.p.x), 100) // moved toward target
        XCTAssertEqual(track.clicks.count, 1)
        XCTAssertEqual(track.clicks[0].point, CGPoint(x: 200, y: 0))
    }

    func test_build_ignoresKeyAndScrollForClicks() {
        let log = EventLog(duration: 1, screenSize: CGSize(width: 100, height: 100), events: [
            .key(t: 0.1),
            .scroll(t: 0.2, point: CGPoint(x: 5, y: 5), deltaY: 1)
        ])
        let track = CursorTrackBuilder(smoother: SpringSmoother()).build(from: log)
        XCTAssertTrue(track.clicks.isEmpty)
        XCTAssertTrue(track.samples.isEmpty)
    }
}
