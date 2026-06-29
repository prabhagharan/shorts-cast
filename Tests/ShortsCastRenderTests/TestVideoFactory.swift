// Tests/ShortsCastRenderTests/TestVideoFactory.swift
import AVFoundation
import CoreImage
import CoreVideo
import CoreGraphics
@testable import ShortsCastRender

enum TestVideoFactory {
    /// Writes a solid-color H.264 .mov of the given size/duration/fps.
    static func writeSolidColor(to url: URL, size: CGSize, seconds: Double, fps: Int, color: RGBA) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
        let image = CIImage(color: color.ciColor).cropped(to: CGRect(origin: .zero, size: size))
        let total = Int(seconds * Double(fps))
        for i in 0..<total {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            ciContext.render(image, to: pb!)
            let pts = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            adaptor.append(pb!, withPresentationTime: pts)
        }
        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
    }
}
