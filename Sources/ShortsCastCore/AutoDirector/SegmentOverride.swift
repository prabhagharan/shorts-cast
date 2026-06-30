import Foundation
import CoreGraphics

/// A manual edit to a generated focus segment (e.g. the user sets this zoom to 3×).
public struct SegmentOverride: Equatable, Codable {
    public var index: Int
    public var zoom: CGFloat?
    public var center: CGPoint?
    public init(index: Int, zoom: CGFloat? = nil, center: CGPoint? = nil) {
        self.index = index; self.zoom = zoom; self.center = center
    }
}

/// Merges a zoom and/or center edit into the override for `index`, preserving whichever
/// field isn't being set (so editing zoom doesn't wipe a center edit, and vice-versa).
public func upsertOverride(_ overrides: [SegmentOverride], index: Int,
                           zoom: CGFloat?, center: CGPoint?) -> [SegmentOverride] {
    var out = overrides
    if let i = out.firstIndex(where: { $0.index == index }) {
        if let zoom = zoom { out[i].zoom = zoom }
        if let center = center { out[i].center = center }
    } else {
        out.append(SegmentOverride(index: index, zoom: zoom, center: center))
    }
    return out
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
