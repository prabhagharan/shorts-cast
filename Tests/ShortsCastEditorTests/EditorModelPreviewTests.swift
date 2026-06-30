// Tests/ShortsCastEditorTests/EditorModelPreviewTests.swift
import XCTest
import CoreImage
import CoreGraphics
import ShortsCastCore
import ShortsCastRender
@testable import ShortsCastEditor

final class EditorModelPreviewTests: XCTestCase {
    private func openedModel(screen: CGSize) throws -> EditorModel {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("empv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: screen, seconds: 1.0, fps: 15, color: RGBA(0, 1, 0, 1),
                                    events: [.click(t: 0.3, point: CGPoint(x: 600, y: 300), button: .left)])
        let m = EditorModel(); try m.open(bundle); return m
    }

    func test_previewImage_compositesBackgroundAndContent() throws {
        let screen = CGSize(width: 1080, height: 1080)
        let m = try openedModel(screen: screen)
        m.format = .square1x1
        m.style = RenderStyle(background: .solid(RGBA(1, 0, 0, 1)), cornerRadius: 0, shadowOpacity: 0,
                              shadowBlur: 0, shadowOffsetY: 0, paddingFraction: 0.1, cursorRadius: 1,
                              cursorColor: RGBA(0, 0, 0, 1), rippleDuration: 0.5, rippleMaxRadius: 1)
        m.frameSource = FakeFrameSource(solidCIImage(RGBA(0, 1, 0, 1), size: screen)) // green source
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])

        let cg = m.previewImage(at: 0.0)
        XCTAssertNotNil(cg)
        let img = CIImage(cgImage: cg!)
        let center = samplePixel(img, at: CGPoint(x: 540, y: 540), exportSize: m.format.exportSize, context: ctx)
        XCTAssertEqual(center.g, 1, accuracy: 0.2)   // content (green) at center
        let edge = samplePixel(img, at: CGPoint(x: 5, y: 540), exportSize: m.format.exportSize, context: ctx)
        XCTAssertEqual(edge.r, 1, accuracy: 0.2)      // background (red) at edge
    }

    func test_previewImage_noVerticalFlipThroughEditor() throws {
        let screen = CGSize(width: 1080, height: 1080)
        let m = try openedModel(screen: screen)
        m.format = .square1x1
        m.style = RenderStyle(background: .solid(RGBA(0, 0, 1, 1)), cornerRadius: 0, shadowOpacity: 0,
                              shadowBlur: 0, shadowOffsetY: 0, paddingFraction: 0, cursorRadius: 1,
                              cursorColor: RGBA(0, 0, 0, 1), rippleDuration: 0.5, rippleMaxRadius: 1)
        // visual top red, bottom green
        m.frameSource = FakeFrameSource(twoToneCIImage(top: RGBA(1, 0, 0, 1), bottom: RGBA(0, 1, 0, 1), size: screen))
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        let cg = m.previewImage(at: 0.0)!
        let img = CIImage(cgImage: cg)
        let top = samplePixel(img, at: CGPoint(x: 540, y: 1000), exportSize: m.format.exportSize, context: ctx)
        let bottom = samplePixel(img, at: CGPoint(x: 540, y: 80), exportSize: m.format.exportSize, context: ctx)
        XCTAssertEqual(top.r, 1, accuracy: 0.25)      // source visual-top -> output visual-top
        XCTAssertEqual(bottom.g, 1, accuracy: 0.25)
    }
}
