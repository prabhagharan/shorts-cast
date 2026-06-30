// Sources/ShortsCastCapture/AVScreenCaptureSession.swift
import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics
import ShortsCastCore

/// Captures a display (optionally cropped) via AVCaptureScreenInput and writes H.264 .mov,
/// anchoring t=0 on the first frame. Replaces the ScreenCaptureKit session.
public final class AVScreenCaptureSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public enum CaptureError: Error { case inputUnavailable, cannotAddInput, cannotAddOutput, writerSetupFailed }

    private let outputURL: URL
    private let displayID: CGDirectDisplayID
    private let cropRect: CGRect?
    private let pixelSize: CGSize

    private let session = AVCaptureSession()
    private let sampleQueue = DispatchQueue(label: "shortscast.avcapture.samples")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    public private(set) var firstFramePTSSeconds: Double?
    public private(set) var writerError: Error?

    public init(outputURL: URL, displayID: CGDirectDisplayID, cropRect: CGRect?, pixelSize: CGSize) {
        self.outputURL = outputURL; self.displayID = displayID
        self.cropRect = cropRect; self.pixelSize = pixelSize
    }

    deinit { session.stopRunning() }

    private func makeWriter() throws {
        let w = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixelSize.width),
            AVVideoHeightKey: Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: VideoQuality.bitrate(for: pixelSize),
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        i.expectsMediaDataInRealTime = true
        let a = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: nil)
        guard w.canAdd(i) else { throw CaptureError.writerSetupFailed }
        w.add(i)
        writer = w; input = i; adaptor = a
    }

    public func start() async throws {
        try makeWriter()
        guard let screenInput = AVCaptureScreenInput(displayID: displayID) else { throw CaptureError.inputUnavailable }
        screenInput.capturesCursor = false
        screenInput.minFrameDuration = CMTime(value: 1, timescale: 60)
        if let crop = cropRect { screenInput.cropRect = crop }

        session.beginConfiguration()
        guard session.canAddInput(screenInput) else { session.commitConfiguration(); throw CaptureError.cannotAddInput }
        session.addInput(screenInput)
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = false
        out.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(out) else { session.commitConfiguration(); throw CaptureError.cannotAddOutput }
        session.addOutput(out)
        session.commitConfiguration()
        session.startRunning()
    }

    public func stop() async -> (firstFrameT: Double, endT: Double) {
        session.stopRunning()
        // Drain in-flight sample callbacks before reading state they write.
        await withCheckedContinuation { cont in sampleQueue.async { cont.resume() } }
        let end = machNowSeconds()
        if let w = writer, w.status == .writing {
            input?.markAsFinished()
            await w.finishWriting()
            writerError = w.error
        } else {
            writerError = writer?.error
        }
        return (firstFramePTSSeconds ?? end, end)
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let writer = writer, let input = input, let adaptor = adaptor,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if writer.status == .unknown {
            guard writer.startWriting() else { writerError = writer.error ?? CaptureError.writerSetupFailed; return }
            writer.startSession(atSourceTime: pts)
            firstFramePTSSeconds = CMTimeGetSeconds(pts)
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        adaptor.append(imageBuffer, withPresentationTime: pts)
    }
}
