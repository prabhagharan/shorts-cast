// Tests/ShortsCastRenderTests/ExportJobOverridesTests.swift
import XCTest
import AVFoundation
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastRender

final class ExportJobOverridesTests: XCTestCase {
    func test_run_acceptsOverrides_andExports() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ejo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let screen = CGSize(width: 1280, height: 720)
        let raw = tmp.appendingPathComponent("src.mov")
        try TestVideoFactory.writeSolidColor(to: raw, size: screen, seconds: 0.5, fps: 15,
                                             color: RGBA(0, 0.4, 0.9, 1))
        let log = EventLog(duration: 0.5, screenSize: screen,
                           events: [.click(t: 0.2, point: CGPoint(x: 640, y: 360), button: .left)])
        let meta = BundleMeta(targetKind: "display", displayID: 1, scale: 1,
                              captureRect: CGRect(origin: .zero, size: screen),
                              appVersion: "t", created: "2026-06-30T00:00:00Z")
        let bundle = tmp.appendingPathComponent("clip.shortscast")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: raw, to: bundle)

        let out = tmp.appendingPathComponent("out")
        let urls = try ExportJob.run(bundleURL: bundle, formats: [.vertical9x16],
                                     style: .default, settings: AutoDirectorSettings(), outDir: out,
                                     overrides: [SegmentOverride(index: 0, zoom: 3.9)])
        XCTAssertEqual(urls.count, 1)
        let v = AVAsset(url: urls[0]).tracks(withMediaType: .video).first!
        XCTAssertEqual(v.naturalSize.width, 1080, accuracy: 1)
        XCTAssertEqual(v.naturalSize.height, 1920, accuracy: 1)
    }
}
