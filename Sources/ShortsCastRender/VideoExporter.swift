// Sources/ShortsCastRender/VideoExporter.swift
import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreMedia
import CoreGraphics
import ShortsCastCore

public enum VideoExporter {
    public enum ExportError: Error { case noVideoTrack, noFramesRendered, writerFailed(Error?) }

    public static func export(rawVideoURL: URL, result: DirectorResult, format: OutputFormat,
                              style: RenderStyle, screenSize: CGSize, to outURL: URL) throws {
        let asset = AVAsset(url: rawVideoURL)
        guard let track = asset.tracks(withMediaType: .video).first else { throw ExportError.noVideoTrack }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(readerOutput)

        try? FileManager.default.removeItem(at: outURL)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(format.exportSize.width),
            AVVideoHeightKey: Int(format.exportSize.height)
        ])
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput,
                                                           sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(format.exportSize.width),
            kCVPixelBufferHeightKey as String: Int(format.exportSize.height)
        ])
        writer.add(writerInput)

        let compositor = FrameCompositor(style: style, format: format, screenSize: screenSize)
        let director = Director(settings: AutoDirectorSettings())

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pixelBufferPool = adaptor.pixelBufferPool else {
            throw ExportError.writerFailed(writer.error)
        }

        var rendered = 0
        while let sample = readerOutput.copyNextSampleBuffer() {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let t = CMTimeGetSeconds(pts)
            let crop = director.cropRect(result, at: t, format: format, screen: screenSize)
            let ciSource = CIImage(cvPixelBuffer: imageBuffer)
            let composedImage = compositor.composite(source: ciSource, crop: crop, time: t,
                                                      cursor: result.cursor)

            while !writerInput.isReadyForMoreMediaData { usleep(1000) }
            var outBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outBuffer)
            guard let pb = outBuffer else { continue }
            compositor.context.render(composedImage, to: pb)
            adaptor.append(pb, withPresentationTime: pts)
            rendered += 1
        }

        writerInput.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()

        if writer.status == .failed {
            try? FileManager.default.removeItem(at: outURL)
            throw ExportError.writerFailed(writer.error)
        }
        if rendered == 0 {
            try? FileManager.default.removeItem(at: outURL)
            throw ExportError.noFramesRendered
        }
    }
}
