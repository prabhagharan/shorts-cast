// Tests/ShortsCastRenderTests/ExportJobTests.swift
import XCTest
import AVFoundation
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastRender

final class ExportJobTests: XCTestCase {
    func test_run_exportsOneMP4PerFormat() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ejob-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Build a synthetic .shortscast bundle.
        let screen = CGSize(width: 1280, height: 720)
        let raw = tmp.appendingPathComponent("src.mov")
        try TestVideoFactory.writeSolidColor(to: raw, size: screen, seconds: 1.0, fps: 30,
                                             color: RGBA(0, 0.5, 1, 1))
        let log = EventLog(duration: 1.0, screenSize: screen,
                           events: [.click(t: 0.4, point: CGPoint(x: 600, y: 300), button: .left)])
        let meta = BundleMeta(targetKind: "display", displayID: 1, scale: 1,
                              captureRect: CGRect(origin: .zero, size: screen),
                              appVersion: "test", created: "2026-06-30T00:00:00Z")
        let bundle = tmp.appendingPathComponent("clip.shortscast")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: raw, to: bundle)

        let outDir = tmp.appendingPathComponent("out")
        let urls = try ExportJob.run(bundleURL: bundle,
                                     formats: [.vertical9x16, .square1x1],
                                     style: .default, settings: AutoDirectorSettings(), outDir: outDir)

        XCTAssertEqual(urls.count, 2)
        for u in urls { XCTAssertTrue(FileManager.default.fileExists(atPath: u.path)) }
        let v = AVAsset(url: urls[0]).tracks(withMediaType: .video).first!
        XCTAssertEqual(v.naturalSize.width, 1080, accuracy: 1)
        XCTAssertEqual(v.naturalSize.height, 1920, accuracy: 1)
    }
}
