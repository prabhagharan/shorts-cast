import Foundation
import CoreGraphics

/// Maps global CGEvent points (top-left origin, points) into the captured
/// area's pixel space (top-left origin). CGEvent and CGDisplayBounds share the
/// same top-left global origin, so this is translate-then-scale with no Y flip.
public struct CaptureGeometry: Equatable {
    public let captureRect: CGRect   // global points
    public let scale: CGFloat        // pixels per point

    public init(captureRect: CGRect, scale: CGFloat) {
        self.captureRect = captureRect
        self.scale = scale
    }

    /// Output video pixel dimensions.
    public var pixelSize: CGSize {
        CGSize(width: captureRect.width * scale, height: captureRect.height * scale)
    }

    /// Maps a global point to captured-area pixels, or nil if outside the area.
    public func mapToPixels(_ global: CGPoint) -> CGPoint? {
        let x = (global.x - captureRect.minX) * scale
        let y = (global.y - captureRect.minY) * scale
        let size = pixelSize
        guard x >= 0, y >= 0, x <= size.width, y <= size.height else { return nil }
        return CGPoint(x: x, y: y)
    }
}
