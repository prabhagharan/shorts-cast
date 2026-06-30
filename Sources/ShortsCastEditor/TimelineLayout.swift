// Sources/ShortsCastEditor/TimelineLayout.swift
import Foundation
import CoreGraphics
import ShortsCastCore

/// Pure geometry: maps focus segments to x-positioned rects within a timeline band.
public enum TimelineLayout {
    public static func xPositions(segments: [FocusSegment], duration: Seconds,
                                  width: CGFloat, height: CGFloat) -> [CGRect] {
        guard duration > 0, width > 0 else { return [] }
        return segments.map { seg in
            let x0 = max(0, min(CGFloat(seg.start / duration) * width, width))
            let x1 = max(0, min(CGFloat(seg.end / duration) * width, width))
            return CGRect(x: x0, y: 0, width: max(0, x1 - x0), height: height)
        }
    }
}
