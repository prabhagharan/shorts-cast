// Tests/ShortsCastRenderTests/RenderTestSupport.swift
import CoreImage
import CoreGraphics
@testable import ShortsCastRender

/// Renders `image` to a bitmap and returns the pixel at `p` (export/CI space, bottom-left origin).
func samplePixel(_ image: CIImage, at p: CGPoint, exportSize: CGSize, context: CIContext) -> RGBA {
    let rect = CGRect(origin: .zero, size: exportSize)
    let cg = context.createCGImage(image, from: rect)!
    let cs = CGColorSpaceCreateDeviceRGB()
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw the full image shifted so that pixel p lands in the 1x1 context.
    ctx.draw(cg, in: CGRect(x: -p.x, y: -p.y, width: exportSize.width, height: exportSize.height))
    return RGBA(Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255, Double(px[3]) / 255)
}

/// A solid-color CIImage of the given size (premultiplied, opaque).
func solidImage(_ color: RGBA, size: CGSize) -> CIImage {
    CIImage(color: color.ciColor).cropped(to: CGRect(origin: .zero, size: size))
}
