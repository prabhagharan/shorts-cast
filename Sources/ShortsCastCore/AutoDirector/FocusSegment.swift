// Sources/ShortsCastCore/AutoDirector/FocusSegment.swift
import Foundation
import CoreGraphics

/// A clustered window of activity the camera should focus on.
public struct FocusSegment: Equatable {
    public var start: Seconds
    public var end: Seconds
    public var center: CGPoint
    public var zoom: CGFloat
    public init(start: Seconds, end: Seconds, center: CGPoint, zoom: CGFloat) {
        self.start = start; self.end = end; self.center = center; self.zoom = zoom
    }
}
