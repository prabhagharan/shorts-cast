// Tests/ShortsCastRenderTests/FrameCompositorCursorTests.swift
import XCTest
import CoreImage
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastRender

final class FrameCompositorCursorTests: XCTestCase {
    private func style() -> RenderStyle {
        RenderStyle(background: .solid(RGBA(1, 0, 0, 1)), cornerRadius: 0, shadowOpacity: 0,
                    shadowBlur: 0, shadowOffsetY: 0, paddingFraction: 0.0, cursorRadius: 40,
                    cursorColor: RGBA(0, 0, 1, 1), rippleDuration: 0.5, rippleMaxRadius: 80)
    }

    func test_cursor_drawnAtMappedPosition() {
        let screen = CGSize(width: 1080, height: 1080)
        let fmt = OutputFormat.square1x1 // 1080x1080
        let comp = FrameCompositor(style: style(), format: fmt, screenSize: screen)
        let source = solidImage(RGBA(0, 1, 0, 1), size: screen) // green
        // Cursor at the center of the screen (source TL coords) the whole time.
        let cursor = CursorTrack(samples: [TimedPoint(t: 0, p: CGPoint(x: 540, y: 540))], clicks: [])
        let out = comp.composite(source: source, crop: CGRect(x: 0, y: 0, width: 1080, height: 1080),
                                 time: 0, cursor: cursor)
        // With padding 0 and a full-screen crop, center maps to export center; cursor is blue there.
        let center = samplePixel(out, at: CGPoint(x: 540, y: 540), exportSize: fmt.exportSize, context: comp.context)
        XCTAssertEqual(center.b, 1, accuracy: 0.2)
        XCTAssertLessThan(center.g, 0.5) // green content covered by blue cursor
    }
}
