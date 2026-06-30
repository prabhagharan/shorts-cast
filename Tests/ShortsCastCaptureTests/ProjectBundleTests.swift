// Tests/ShortsCastCaptureTests/ProjectBundleTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastCapture

final class ProjectBundleTests: XCTestCase {
    func test_writeThenRead_roundTrips() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scbundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // a stand-in "raw video" file
        let fakeMov = tmp.appendingPathComponent("src.mov")
        try Data("not really a movie".utf8).write(to: fakeMov)

        let log = EventLog(duration: 4, screenSize: CGSize(width: 1920, height: 1080),
                           events: [.click(t: 1, point: CGPoint(x: 10, y: 20), button: .left)])
        let meta = BundleMeta(targetKind: "display", displayID: 1, scale: 2,
                              captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
                              appVersion: "0.1.0", created: "2026-06-29T00:00:00Z")

        let bundle = tmp.appendingPathComponent("out.shortscast")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: fakeMov, to: bundle)

        let read = try ProjectBundle.read(bundle)
        XCTAssertEqual(read.eventLog, log)
        XCTAssertEqual(read.meta, meta)
        XCTAssertTrue(FileManager.default.fileExists(atPath: read.rawVideoURL.path))
    }

    func test_write_missingRawVideo_throws() {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("x.shortscast")
        let log = EventLog(duration: 0, screenSize: .zero, events: [])
        let meta = BundleMeta(targetKind: "display", displayID: nil, scale: 1,
                              captureRect: .zero, appVersion: "0", created: "t")
        XCTAssertThrowsError(try ProjectBundle.write(
            eventLog: log, meta: meta,
            rawVideo: URL(fileURLWithPath: "/no/such/file.mov"), to: bundle))
    }

    func test_write_overwritesExistingBundle() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scbundle-overwrite-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fakeMov = tmp.appendingPathComponent("src.mov")
        try Data("v1".utf8).write(to: fakeMov)
        let log = EventLog(duration: 1, screenSize: CGSize(width: 100, height: 100), events: [])
        let meta = BundleMeta(targetKind: "display", displayID: 1, scale: 1,
                              captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                              appVersion: "0", created: "t")
        let bundle = tmp.appendingPathComponent("out.shortscast")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: fakeMov, to: bundle)
        // Writing again to the same bundle path must NOT throw (overwrites raw.mov).
        let fakeMov2 = tmp.appendingPathComponent("src2.mov")
        try Data("v2-longer-contents".utf8).write(to: fakeMov2)
        XCTAssertNoThrow(try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: fakeMov2, to: bundle))
        let written = try Data(contentsOf: bundle.appendingPathComponent("raw.mov"))
        XCTAssertEqual(String(data: written, encoding: .utf8), "v2-longer-contents")
    }
}
