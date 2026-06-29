import XCTest
import CoreImage
import CoreVideo
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastRender

final class FrameCompositorOrientationTests: XCTestCase {
    /// 32BGRA buffer: rows 0..<h/2 (visual TOP) = topBGRA, rows h/2..<h (visual bottom) = bottomBGRA.
    private func twoToneBuffer(width: Int, height: Int,
                               top: (UInt8, UInt8, UInt8, UInt8),
                               bottom: (UInt8, UInt8, UInt8, UInt8)) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &pb)
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        let base = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(buf)
        for row in 0..<height {
            let c = row < height / 2 ? top : bottom
            let rowPtr = base + row * bpr
            for col in 0..<width {
                rowPtr[col * 4 + 0] = c.0 // B
                rowPtr[col * 4 + 1] = c.1 // G
                rowPtr[col * 4 + 2] = c.2 // R
                rowPtr[col * 4 + 3] = c.3 // A
            }
        }
        CVPixelBufferUnlockBaseAddress(buf, [])
        return buf
    }

    func test_sourceTopMapsToOutputTop_noVerticalFlip() {
        let w = 64, h = 64
        // visual TOP rows = RED (B0 G0 R255), bottom = GREEN (B0 G255 R0)
        let buf = twoToneBuffer(width: w, height: h, top: (0, 0, 255, 255), bottom: (0, 255, 0, 255))
        let source = CIImage(cvPixelBuffer: buf)
        let screen = CGSize(width: w, height: h)
        let fmt = OutputFormat.square1x1 // 1080x1080, matches the 1:1 source
        let style = RenderStyle(background: .solid(RGBA(0, 0, 1, 1)), cornerRadius: 0, shadowOpacity: 0,
                                shadowBlur: 0, shadowOffsetY: 0, paddingFraction: 0, cursorRadius: 1,
                                cursorColor: RGBA(0, 0, 0, 1), rippleDuration: 0.5, rippleMaxRadius: 1)
        let comp = FrameCompositor(style: style, format: fmt, screenSize: screen)
        let out = comp.composite(source: source,
                                 crop: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                                 time: 0, cursor: CursorTrack(samples: [], clicks: []))

        // samplePixel uses CI/export bottom-left coords: visual TOP of the frame is HIGH y.
        let topPixel = samplePixel(out, at: CGPoint(x: 540, y: 1000), exportSize: fmt.exportSize, context: comp.context)
        let bottomPixel = samplePixel(out, at: CGPoint(x: 540, y: 80), exportSize: fmt.exportSize, context: comp.context)

        // Source visual top is red -> must appear at output visual top (high y).
        XCTAssertEqual(topPixel.r, 1, accuracy: 0.25)
        XCTAssertLessThan(topPixel.g, 0.35)
        XCTAssertEqual(bottomPixel.g, 1, accuracy: 0.25)
        XCTAssertLessThan(bottomPixel.r, 0.35)
    }
}
