// Tests/ShortsCastEditorTests/EditorModelPersistenceTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastRender
@testable import ShortsCastEditor

final class EditorModelPersistenceTests: XCTestCase {
    func test_saveThenReopen_restoresEdits() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("emp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: CGSize(width: 1280, height: 720), seconds: 1.0, fps: 15,
                                    color: RGBA(0, 0.5, 1, 1),
                                    events: [.click(t: 0.3, point: CGPoint(x: 600, y: 300), button: .left),
                                             .click(t: 0.35, point: CGPoint(x: 610, y: 305), button: .left)])
        let m = EditorModel(); try m.open(bundle)
        m.setZoom(segment: 0, zoom: 3.3)
        m.format = .square1x1
        m.settings.defaultZoom = 2.8
        try m.save()

        let m2 = EditorModel(); try m2.open(bundle)
        XCTAssertEqual(m2.overrides, [SegmentOverride(index: 0, zoom: 3.3)])
        XCTAssertEqual(m2.format.name, "1:1")
        XCTAssertEqual(m2.settings.defaultZoom, 2.8, accuracy: 1e-6)
        XCTAssertEqual(m2.segments[0].zoom, 3.3, accuracy: 1e-6) // override re-applied
    }

    func test_open_toleratesMissingProjectJSON() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("emp2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: CGSize(width: 1280, height: 720), seconds: 1.0, fps: 15,
                                    color: RGBA(0, 0.5, 1, 1),
                                    events: [.click(t: 0.3, point: CGPoint(x: 600, y: 300), button: .left)])
        let m = EditorModel(); try m.open(bundle) // no project.json present
        XCTAssertTrue(m.overrides.isEmpty)
        XCTAssertEqual(m.format.name, "9:16")
    }
}
