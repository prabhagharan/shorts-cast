// Tests/ShortsCastCoreTests/EventLogTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class EventLogTests: XCTestCase {
    func test_eventLog_jsonRoundTrip_preservesEvents() throws {
        let log = EventLog(
            duration: 5,
            screenSize: CGSize(width: 1920, height: 1080),
            events: [
                .click(t: 1.0, point: CGPoint(x: 100, y: 200), button: .left),
                .key(t: 1.2),
                .scroll(t: 2.0, point: CGPoint(x: 50, y: 60), deltaY: -3),
                .cursor(t: 2.1, point: CGPoint(x: 51, y: 61))
            ]
        )
        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(EventLog.self, from: data)
        XCTAssertEqual(decoded, log)
        XCTAssertEqual(decoded.events[1].type, .key)
        XCTAssertNil(decoded.events[1].point)
    }
}
