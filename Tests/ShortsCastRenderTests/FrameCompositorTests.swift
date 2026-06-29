// Tests/ShortsCastRenderTests/FrameCompositorTests.swift
import XCTest
import CoreImage
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastRender

final class FrameCompositorTests: XCTestCase {
    private func style(bg: RGBA) -> RenderStyle {
        RenderStyle(background: .solid(bg), cornerRadius: 0, shadowOpacity: 0, shadowBlur: 0,
                    shadowOffsetY: 0, paddingFraction: 0.1, cursorRadius: 18,
                    cursorColor: RGBA(0, 0, 1, 1), rippleDuration: 0.5, rippleMaxRadius: 60)
    }

    func test_backgroundAndContent_areComposited() {
        let screen = CGSize(width: 1000, height: 1000)
        let fmt = OutputFormat.square1x1 // 1080x1080, aspect matches a 1000x1000 crop
        let bg = RGBA(1, 0, 0, 1)        // red background
        let comp = FrameCompositor(style: style(bg: bg), format: fmt, screenSize: screen)
        let source = solidImage(RGBA(0, 1, 0, 1), size: screen) // green screen content
        let crop = CGRect(x: 0, y: 0, width: 1000, height: 1000) // full screen
        let out = comp.composite(source: source, crop: crop, time: 0, cursor: CursorTrack(samples: [], clicks: []))

        // Center is inside the content rect -> green.
        let center = samplePixel(out, at: CGPoint(x: 540, y: 540), exportSize: fmt.exportSize, context: comp.context)
        XCTAssertEqual(center.g, 1, accuracy: 0.15)
        XCTAssertLessThan(center.r, 0.3)

        // Left-edge middle is in the padding margin -> red background.
        let edge = samplePixel(out, at: CGPoint(x: 5, y: 540), exportSize: fmt.exportSize, context: comp.context)
        XCTAssertEqual(edge.r, 1, accuracy: 0.15)
        XCTAssertLessThan(edge.g, 0.3)
    }
}
