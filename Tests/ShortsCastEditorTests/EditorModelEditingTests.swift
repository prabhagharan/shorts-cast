// Tests/ShortsCastEditorTests/EditorModelEditingTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastRender
@testable import ShortsCastEditor

final class EditorModelEditingTests: XCTestCase {
    private func openedModel() throws -> EditorModel {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eme-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: CGSize(width: 1280, height: 720), seconds: 1.0, fps: 15,
                                    color: RGBA(0, 0.5, 1, 1),
                                    events: [.click(t: 0.3, point: CGPoint(x: 600, y: 300), button: .left),
                                             .click(t: 0.35, point: CGPoint(x: 610, y: 305), button: .left)])
        let m = EditorModel(); try m.open(bundle); return m
    }

    func test_setZoom_overridesSegmentZoom() throws {
        let m = try openedModel()
        XCTAssertEqual(m.segments.count, 1)
        m.setZoom(segment: 0, zoom: 3.9)
        XCTAssertEqual(m.segments[0].zoom, 3.9, accuracy: 1e-6)
        XCTAssertEqual(m.overrides.count, 1)
    }

    func test_setZoom_isIdempotentPerSegment() throws {
        let m = try openedModel()
        m.setZoom(segment: 0, zoom: 3.0)
        m.setZoom(segment: 0, zoom: 2.2)
        XCTAssertEqual(m.overrides.count, 1)          // replaced, not duplicated
        XCTAssertEqual(m.segments[0].zoom, 2.2, accuracy: 1e-6)
    }

    func test_clearOverride_reverts() throws {
        let m = try openedModel()
        let original = m.segments[0].zoom
        m.setZoom(segment: 0, zoom: 3.9)
        m.clearOverride(segment: 0)
        XCTAssertTrue(m.overrides.isEmpty)
        XCTAssertEqual(m.segments[0].zoom, original, accuracy: 1e-6)
    }

    func test_maxZoomSetting_capsGeneratedZoom() throws {
        let m = try openedModel()
        m.settings.defaultZoom = 5.0
        m.settings.maxZoom = 2.0   // didSet regenerates; clamps generated zoom
        XCTAssertLessThanOrEqual(m.segments[0].zoom, 2.0 + 1e-6)
    }
}
