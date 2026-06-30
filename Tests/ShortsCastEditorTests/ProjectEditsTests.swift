// Tests/ShortsCastEditorTests/ProjectEditsTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastRender
@testable import ShortsCastEditor

final class ProjectEditsTests: XCTestCase {
    func test_roundTrip() throws {
        var settings = AutoDirectorSettings(); settings.defaultZoom = 2.9
        let edits = ProjectEdits(
            overrides: [SegmentOverride(index: 0, zoom: 3.5)],
            style: .default, formatName: "1:1", settings: settings)
        let decoded = try JSONDecoder().decode(ProjectEdits.self, from: JSONEncoder().encode(edits))
        XCTAssertEqual(decoded, edits)
    }
}
