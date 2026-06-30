// Tests/ShortsCastEditorTests/EditorTestSupport.swift
import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
import ShortsCastRender
@testable import ShortsCastEditor

enum TestVideoFactory {
    static func writeSolidColor(to url: URL, size: CGSize, seconds: Double, fps: Int, color: RGBA) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        let image = CIImage(color: color.ciColor).cropped(to: CGRect(origin: .zero, size: size))
        for i in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            ctx.render(image, to: pb!)
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0); writer.finishWriting { sema.signal() }; sema.wait()
    }
}

final class FakeFrameSource: FrameSource {
    let image: CIImage
    init(_ image: CIImage) { self.image = image }
    func image(at t: Seconds) -> CIImage? { image }
}

func solidCIImage(_ color: RGBA, size: CGSize) -> CIImage {
    CIImage(color: color.ciColor).cropped(to: CGRect(origin: .zero, size: size))
}

/// Top half (visual top) = `top`, bottom half = `bottom`. Built via CG so orientation is unambiguous.
func twoToneCIImage(top: RGBA, bottom: RGBA, size: CGSize) -> CIImage {
    let w = Int(size.width), h = Int(size.height)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // CGContext is bottom-left; draw bottom color in lower half, top color in upper half.
    ctx.setFillColor(CGColor(red: CGFloat(bottom.r), green: CGFloat(bottom.g), blue: CGFloat(bottom.b), alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 2))
    ctx.setFillColor(CGColor(red: CGFloat(top.r), green: CGFloat(top.g), blue: CGFloat(top.b), alpha: 1))
    ctx.fill(CGRect(x: 0, y: h / 2, width: w, height: h - h / 2))
    return CIImage(cgImage: ctx.makeImage()!)
}

func samplePixel(_ image: CIImage, at p: CGPoint, exportSize: CGSize, context: CIContext) -> RGBA {
    let cg = context.createCGImage(image, from: CGRect(origin: .zero, size: exportSize))!
    let cs = CGColorSpaceCreateDeviceRGB()
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: -p.x, y: -p.y, width: exportSize.width, height: exportSize.height))
    return RGBA(Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255, Double(px[3]) / 255)
}

/// Writes a `.shortscast` bundle (raw.mov + events.json + meta.json) and returns its URL.
func makeBundle(in dir: URL, screen: CGSize, seconds: Double, fps: Int, color: RGBA,
                events: [RecordingEvent]) throws -> URL {
    let raw = dir.appendingPathComponent("src.mov")
    try TestVideoFactory.writeSolidColor(to: raw, size: screen, seconds: seconds, fps: fps, color: color)
    let log = EventLog(duration: seconds, screenSize: screen, events: events)
    let meta = BundleMeta(targetKind: "display", displayID: 1, scale: 1,
                          captureRect: CGRect(origin: .zero, size: screen),
                          appVersion: "test", created: "2026-06-30T00:00:00Z")
    let bundle = dir.appendingPathComponent("clip.shortscast")
    try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: raw, to: bundle)
    return bundle
}
