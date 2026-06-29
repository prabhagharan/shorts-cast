// Sources/ShortsCastRender/FrameCompositor.swift
import Foundation
import CoreImage
import CoreGraphics
import CoreVideo
import ShortsCastCore

public final class FrameCompositor {
    public let style: RenderStyle
    public let format: OutputFormat
    public let screenSize: CGSize
    public let context: CIContext

    let exportSize: CGSize
    let contentRect: CGRect
    private let background: CIImage
    private let roundedMask: CIImage
    private let shadow: CIImage
    private let cursorDot: CIImage
    private let ringUnit: CIImage

    public init(style: RenderStyle, format: OutputFormat, screenSize: CGSize) {
        self.style = style
        self.format = format
        self.screenSize = screenSize
        // Disable color management so rendered pixel values match configured colors (predictable tests).
        self.context = CIContext(options: [.workingColorSpace: NSNull()])
        self.exportSize = format.exportSize
        self.contentRect = FrameLayout.contentRect(exportSize: format.exportSize,
                                                    paddingFraction: style.paddingFraction)
        self.background = FrameCompositor.makeBackground(style.background, size: format.exportSize)
        self.roundedMask = FrameCompositor.makeRoundedMask(size: contentRect.size, radius: style.cornerRadius)
        self.shadow = FrameCompositor.makeShadow(maskSize: contentRect.size, radius: style.cornerRadius,
                                                 contentOrigin: contentRect.origin, style: style)
        self.cursorDot = FrameCompositor.makeFilledCircle(radius: style.cursorRadius, color: style.cursorColor)
        self.ringUnit = FrameCompositor.makeRing(radius: 100, thickness: 12, color: style.cursorColor)
    }

    public func composite(source: CIImage, crop: CGRect, time: Seconds, cursor: CursorTrack) -> CIImage {
        // Map the top-left source crop into CI bottom-left space.
        let ciCrop = CGRect(x: crop.minX, y: screenSize.height - crop.maxY,
                            width: crop.width, height: crop.height)
        var content = source.cropped(to: ciCrop)
            .transformed(by: CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY))
        let sx = contentRect.width / crop.width
        let sy = contentRect.height / crop.height
        content = content
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: contentRect.minX, y: contentRect.minY))

        let mask = roundedMask.transformed(by: CGAffineTransform(translationX: contentRect.minX,
                                                                 y: contentRect.minY))
        let rounded = content.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": CIImage.empty(),
            "inputMaskImage": mask
        ])

        var layered = rounded.composited(over: shadow).composited(over: background)

        // Click ripples (under the cursor dot).
        for r in CursorRenderer.activeRipples(at: time, clicks: cursor.clicks, duration: style.rippleDuration) {
            guard let p = sourceToExport(r.point, crop: crop) else { continue }
            let radius = style.cursorRadius + (style.rippleMaxRadius - style.cursorRadius) * CGFloat(r.progress)
            let scale = radius / 100.0 // ringUnit was built at radius 100
            let alpha = CGFloat(1.0 - r.progress)
            let ring = ringUnit
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
                ])
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: p.x - radius, y: p.y - radius))
            layered = ring.composited(over: layered)
        }

        // Cursor dot.
        if let cp = CursorRenderer.position(at: time, samples: cursor.samples),
           let p = sourceToExport(cp, crop: crop) {
            let dot = cursorDot.transformed(by: CGAffineTransform(translationX: p.x - style.cursorRadius,
                                                                  y: p.y - style.cursorRadius))
            layered = dot.composited(over: layered)
        }

        return layered.cropped(to: CGRect(origin: .zero, size: exportSize))
    }

    // MARK: - Precomputed layers

    static func makeBackground(_ bg: RenderStyle.Background, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        switch bg {
        case .solid(let c):
            return CIImage(color: c.ciColor).cropped(to: rect)
        case .gradient(let top, let bottom):
            let f = CIFilter(name: "CILinearGradient")!
            f.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
            f.setValue(CIVector(x: 0, y: size.height), forKey: "inputPoint1")
            f.setValue(bottom.ciColor, forKey: "inputColor0")
            f.setValue(top.ciColor, forKey: "inputColor1")
            return f.outputImage!.cropped(to: rect)
        }
    }

    /// A white rounded-rectangle alpha mask of `size`, origin (0,0).
    static func makeRoundedMask(size: CGSize, radius: CGFloat) -> CIImage {
        let w = max(1, Int(size.width.rounded())), h = max(1, Int(size.height.rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let r = max(0, min(radius, CGFloat(min(w, h)) / 2))
        let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                          cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.addPath(path); ctx.fillPath()
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// A filled circle CIImage centered at (radius, radius), size 2*radius square.
    static func makeFilledCircle(radius: CGFloat, color: RGBA) -> CIImage {
        let d = max(2, Int((radius * 2).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: d, height: d, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: d, height: d))
        ctx.setFillColor(CGColor(red: CGFloat(color.r), green: CGFloat(color.g),
                                 blue: CGFloat(color.b), alpha: CGFloat(color.a)))
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// A ring (stroked circle) CIImage of outer `radius`, centered, size 2*radius square.
    static func makeRing(radius: CGFloat, thickness: CGFloat, color: RGBA) -> CIImage {
        let d = max(2, Int((radius * 2).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: d, height: d, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: d, height: d))
        ctx.setStrokeColor(CGColor(red: CGFloat(color.r), green: CGFloat(color.g),
                                   blue: CGFloat(color.b), alpha: CGFloat(color.a)))
        ctx.setLineWidth(thickness)
        let inset = thickness / 2
        ctx.strokeEllipse(in: CGRect(x: inset, y: inset, width: CGFloat(d) - 2 * inset,
                                     height: CGFloat(d) - 2 * inset))
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Maps a source-pixel (top-left) point into export CI space (bottom-left), or nil if outside the crop.
    func sourceToExport(_ point: CGPoint, crop: CGRect) -> CGPoint? {
        guard crop.contains(point) else { return nil }
        let ciY = screenSize.height - point.y                 // to source CI space
        let ciCropY = screenSize.height - crop.maxY
        let localX = (point.x - crop.minX) * (contentRect.width / crop.width)
        let localY = (ciY - ciCropY) * (contentRect.height / crop.height)
        return CGPoint(x: contentRect.minX + localX, y: contentRect.minY + localY)
    }

    /// A soft drop shadow placed under the content rect.
    static func makeShadow(maskSize: CGSize, radius: CGFloat, contentOrigin: CGPoint,
                           style: RenderStyle) -> CIImage {
        let mask = makeRoundedMask(size: maskSize, radius: radius)
        let black = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(style.shadowOpacity)),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        let blurred = black.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": style.shadowBlur
        ])
        // Offset downward in screen terms => negative y in CI bottom-left space.
        return blurred.transformed(by: CGAffineTransform(translationX: contentOrigin.x,
                                                         y: contentOrigin.y - style.shadowOffsetY))
    }
}
