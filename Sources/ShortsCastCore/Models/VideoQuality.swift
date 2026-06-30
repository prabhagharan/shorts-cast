// Sources/ShortsCastCore/Models/VideoQuality.swift
import Foundation
import CoreGraphics

/// H.264 encoding quality. The writers set no bitrate by default, so AVFoundation
/// picks a low one and footage looks soft; this gives a high, resolution-aware target.
public enum VideoQuality {
    /// ~8 bits per pixel of average bitrate — visually high quality, scales with area.
    public static func bitrate(width: Int, height: Int) -> Int {
        max(width * height * 8, 4_000_000)
    }

    public static func bitrate(for size: CGSize) -> Int {
        bitrate(width: Int(size.width), height: Int(size.height))
    }
}
