// Sources/ShortsCastEditor/FrameSource.swift
import Foundation
import AVFoundation
import CoreImage
import CoreMedia
import ShortsCastCore

/// Supplies a source video frame (as a CIImage) at a given recording time.
public protocol FrameSource {
    func image(at t: Seconds) -> CIImage?
}

/// Decodes frames from a `.mov` via AVAssetImageGenerator (upright CGImage -> CIImage).
public final class AVAssetFrameSource: FrameSource {
    private let generator: AVAssetImageGenerator

    public init(url: URL) {
        let asset = AVAsset(url: url)
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        g.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        generator = g
    }

    public func image(at t: Seconds) -> CIImage? {
        let time = CMTime(seconds: max(0, t), preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return CIImage(cgImage: cg)
    }
}
