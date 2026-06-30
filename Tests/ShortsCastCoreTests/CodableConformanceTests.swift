// Tests/ShortsCastCoreTests/CodableConformanceTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class CodableConformanceTests: XCTestCase {
    func test_autoDirectorSettings_roundTripsAndEquates() throws {
        var s = AutoDirectorSettings()
        s.defaultZoom = 3.3
        s.maxZoom = 5.0
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AutoDirectorSettings.self, from: data)
        XCTAssertEqual(decoded, s)
        XCTAssertEqual(decoded.defaultZoom, 3.3, accuracy: 1e-9)
    }
    func test_segmentOverride_roundTrips() throws {
        let o = SegmentOverride(index: 2, zoom: 3.7, center: CGPoint(x: 10, y: 20))
        let decoded = try JSONDecoder().decode(SegmentOverride.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(decoded, o)
        let o2 = SegmentOverride(index: 1, zoom: nil, center: nil)
        let decoded2 = try JSONDecoder().decode(SegmentOverride.self, from: JSONEncoder().encode(o2))
        XCTAssertEqual(decoded2, o2)
    }
}
