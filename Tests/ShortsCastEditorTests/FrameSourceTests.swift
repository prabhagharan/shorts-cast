// Tests/ShortsCastEditorTests/FrameSourceTests.swift
import XCTest
import AVFoundation
import CoreImage
import CoreGraphics
import ShortsCastRender
@testable import ShortsCastEditor

final class FrameSourceTests: XCTestCase {
    func test_avAssetFrameSource_returnsFrame() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let raw = tmp.appendingPathComponent("v.mov")
        let size = CGSize(width: 320, height: 240)
        try TestVideoFactory.writeSolidColor(to: raw, size: size, seconds: 1.0, fps: 15, color: RGBA(0, 1, 0, 1))

        let src = AVAssetFrameSource(url: raw)
        let img = src.image(at: 0.5)
        XCTAssertNotNil(img)
        XCTAssertEqual(img!.extent.width, 320, accuracy: 2)
        XCTAssertEqual(img!.extent.height, 240, accuracy: 2)
    }
}
