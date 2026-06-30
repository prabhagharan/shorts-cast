// Sources/ShortsCastCore/AutoDirector/FocusSegment.swift
import Foundation
import CoreGraphics

/// A clustered window of activity the camera should focus on.
public struct FocusSegment: Equatable {
    public var start: Seconds
    public var end: Seconds
    public var center: CGPoint
    public var zoom: CGFloat
    /// Per-segment ease durations; nil means use the global AutoDirectorSettings value.
    public var zoomInDuration: Seconds?
    public var zoomOutDuration: Seconds?
    public init(start: Seconds, end: Seconds, center: CGPoint, zoom: CGFloat,
                zoomInDuration: Seconds? = nil, zoomOutDuration: Seconds? = nil) {
        self.start = start; self.end = end; self.center = center; self.zoom = zoom
        self.zoomInDuration = zoomInDuration; self.zoomOutDuration = zoomOutDuration
    }
}
