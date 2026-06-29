// Tests/ShortsCastRenderTests/VideoExporterTests.swift
import XCTest
import AVFoundation
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastRender

final class VideoExporterTests: XCTestCase {
    func test_export_producesMP4WithFormatDimensions() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vexp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let screen = CGSize(width: 1280, height: 720)
        let raw = tmp.appendingPathComponent("raw.mov")
        try TestVideoFactory.writeSolidColor(to: raw, size: screen, seconds: 1.0, fps: 30,
                                             color: RGBA(0, 1, 0, 1))

        let log = EventLog(duration: 1.0, screenSize: screen, events: [
            .click(t: 0.5, point: CGPoint(x: 640, y: 360), button: .left)
        ])
        let result = Director(settings: AutoDirectorSettings()).direct(log: log, overrides: [])

        let out = tmp.appendingPathComponent("out.mp4")
        try VideoExporter.export(rawVideoURL: raw, result: result, format: .vertical9x16,
                                 style: .default, screenSize: screen, to: out)

        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        let track = AVAsset(url: out).tracks(withMediaType: .video).first!
        XCTAssertEqual(track.naturalSize.width, 1080, accuracy: 1)
        XCTAssertEqual(track.naturalSize.height, 1920, accuracy: 1)
        XCTAssertGreaterThan(CMTimeGetSeconds(AVAsset(url: out).duration), 0.5)
    }
}
