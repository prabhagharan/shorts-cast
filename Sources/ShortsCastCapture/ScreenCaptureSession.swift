// Sources/ShortsCastCapture/ScreenCaptureSession.swift
import Foundation
import AVFoundation
import CoreMedia
import CoreImage
import CoreVideo
import ScreenCaptureKit
import CoreGraphics

@available(macOS 12.3, *)
public final class ScreenCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate {
    public enum CaptureError: Error { case writerSetupFailed }

    private let outputURL: URL
    private let pixelSize: CGSize
    private let cropRectPixels: CGRect?
    private let ciContext = CIContext()
    private let sampleQueue = DispatchQueue(label: "shortscast.capture.samples")

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    public private(set) var firstFramePTSSeconds: Double?
    public private(set) var writerError: Error?

    private var diagCallbacks = 0
    private var diagScreenType = 0
    private var diagWithImage = 0

    public init(outputURL: URL, pixelSize: CGSize, cropRectPixels: CGRect?) {
        self.outputURL = outputURL
        self.pixelSize = pixelSize
        self.cropRectPixels = cropRectPixels
    }

    private func makeWriter() throws {
        let w = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixelSize.width),
            AVVideoHeightKey: Int(pixelSize.height)
        ]
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        i.expectsMediaDataInRealTime = true
        let a = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: nil)
        guard w.canAdd(i) else { throw CaptureError.writerSetupFailed }
        w.add(i)
        writer = w; input = i; adaptor = a
    }

    public func start(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws {
        try makeWriter()
        FileHandle.standardError.write(Data("diag(start): writer ready, adding output + starting stream\n".utf8))
        let s = SCStream(filter: filter, configuration: configuration, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        stream = s
        try await s.startCapture()
        FileHandle.standardError.write(Data("diag(start): startCapture returned; config=\(configuration.width)x\(configuration.height) queueDepth=\(configuration.queueDepth)\n".utf8))
    }

    public func stop() async -> (firstFrameT: Double, endT: Double) {
        if let s = stream { try? await s.stopCapture() }
        // Drain any in-flight sample-buffer callback before reading state it writes.
        await withCheckedContinuation { cont in
            sampleQueue.async { cont.resume() }
        }
        let end = machNowSeconds()
        // Finalize only if the writer actually started (a frame arrived). Calling
        // markAsFinished()/finishWriting() while status is .unknown throws.
        if let w = writer, w.status == .writing {
            input?.markAsFinished()
            await w.finishWriting()
            writerError = w.error
        } else {
            writerError = writer?.error
        }
        FileHandle.standardError.write(Data("diag: callbacks=\(diagCallbacks) screenType=\(diagScreenType) withImage=\(diagWithImage) firstFramePTS=\(String(describing: firstFramePTSSeconds)) writerStatus=\(writer?.status.rawValue ?? -1)\n".utf8))
        return (firstFramePTSSeconds ?? end, end)
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write(Data("diag: stream stopped with error: \(error)\n".utf8))
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        diagCallbacks += 1
        guard type == .screen else { return }
        diagScreenType += 1
        guard sampleBuffer.isValid,
              let writer = writer, let input = input, let adaptor = adaptor,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        diagWithImage += 1
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            firstFramePTSSeconds = CMTimeGetSeconds(pts)
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }

        if let crop = cropRectPixels {
            guard let cropped = cropPixelBuffer(imageBuffer, to: crop) else { return }
            adaptor.append(cropped, withPresentationTime: pts)
        } else {
            adaptor.append(imageBuffer, withPresentationTime: pts)
        }
    }

    /// Crops a frame to `rect` (top-left pixel coords) into a new BGRA pixel buffer.
    private func cropPixelBuffer(_ src: CVPixelBuffer, to rect: CGRect) -> CVPixelBuffer? {
        let ci = CIImage(cvPixelBuffer: src)
        let h = CGFloat(CVPixelBufferGetHeight(src))
        // CIImage origin is bottom-left; flip the top-left rect into CI space.
        let ciRect = CGRect(x: rect.minX, y: h - rect.maxY, width: rect.width, height: rect.height)
        let cropped = ci.cropped(to: ciRect)
            .transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY))
        var out: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, Int(rect.width), Int(rect.height),
                            kCVPixelFormatType_32BGRA, attrs, &out)
        guard let dst = out else { return nil }
        ciContext.render(cropped, to: dst)
        return dst
    }
}
