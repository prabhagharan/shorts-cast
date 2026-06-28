import Foundation
import CoreGraphics

/// A manual edit to a generated focus segment (e.g. the user sets this zoom to 3×).
public struct SegmentOverride: Equatable {
    public var index: Int
    public var zoom: CGFloat?
    public var center: CGPoint?
    public init(index: Int, zoom: CGFloat? = nil, center: CGPoint? = nil) {
        self.index = index; self.zoom = zoom; self.center = center
    }
}

/// Applies overrides by segment index; out-of-range indices are ignored.
public func applyOverrides(_ segments: [FocusSegment],
                           _ overrides: [SegmentOverride]) -> [FocusSegment] {
    var out = segments
    for o in overrides where o.index >= 0 && o.index < out.count {
        if let z = o.zoom { out[o.index].zoom = z }
        if let c = o.center { out[o.index].center = c }
    }
    return out
}
