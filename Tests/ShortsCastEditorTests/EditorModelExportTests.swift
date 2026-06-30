// Tests/ShortsCastEditorTests/EditorModelExportTests.swift
import XCTest
import AVFoundation
import CoreGraphics
import ShortsCastCore
import ShortsCastRender
@testable import ShortsCastEditor

final class EditorModelExportTests: XCTestCase {
    func test_export_writesOneMP4PerFormat() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("emx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: CGSize(width: 1280, height: 720), seconds: 0.5, fps: 15,
                                    color: RGBA(0, 0.5, 1, 1),
                                    events: [.click(t: 0.2, point: CGPoint(x: 600, y: 300), button: .left)])
        let m = EditorModel(); try m.open(bundle)
        m.setZoom(segment: 0, zoom: 3.5) // exercise override path through export

        let outDir = tmp.appendingPathComponent("out")
        let urls = try m.export(formats: [OutputFormat.vertical9x16, OutputFormat.square1x1], outDir: outDir)
        XCTAssertEqual(urls.count, 2)
        for u in urls { XCTAssertTrue(FileManager.default.fileExists(atPath: u.path)) }
        let v = AVAsset(url: urls[0]).tracks(withMediaType: .video).first!
        XCTAssertEqual(v.naturalSize.width, 1080, accuracy: 1)
        XCTAssertEqual(v.naturalSize.height, 1920, accuracy: 1)
    }

    func test_export_throwsWhenNotOpen() {
        let m = EditorModel()
        XCTAssertThrowsError(try m.export(formats: [OutputFormat.vertical9x16], outDir: URL(fileURLWithPath: "/tmp/x")))
    }
}
