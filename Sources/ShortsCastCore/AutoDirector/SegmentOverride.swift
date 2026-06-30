import Foundation
import CoreGraphics

/// A manual edit to a generated focus segment (e.g. the user sets this zoom to 3×).
public struct SegmentOverride: Equatable, Codable {
    public var index: Int
    public var zoom: CGFloat?
    public var center: CGPoint?
    public var zoomInDuration: Double?
    public var zoomOutDuration: Double?
    public init(index: Int, zoom: CGFloat? = nil, center: CGPoint? = nil,
                zoomInDuration: Double? = nil, zoomOutDuration: Double? = nil) {
        self.index = index; self.zoom = zoom; self.center = center
        self.zoomInDuration = zoomInDuration; self.zoomOutDuration = zoomOutDuration
    }
}

/// Merges the supplied (non-nil) edits into the override for `index`, preserving whichever
/// fields aren't being set (so editing one field doesn't wipe the others).
public func upsertOverride(_ overrides: [SegmentOverride], index: Int,
                           zoom: CGFloat? = nil, center: CGPoint? = nil,
                           zoomInDuration: Double? = nil, zoomOutDuration: Double? = nil) -> [SegmentOverride] {
    var out = overrides
    if let i = out.firstIndex(where: { $0.index == index }) {
        if let zoom = zoom { out[i].zoom = zoom }
        if let center = center { out[i].center = center }
        if let zoomInDuration = zoomInDuration { out[i].zoomInDuration = zoomInDuration }
        if let zoomOutDuration = zoomOutDuration { out[i].zoomOutDuration = zoomOutDuration }
    } else {
        out.append(SegmentOverride(index: index, zoom: zoom, center: center,
                                   zoomInDuration: zoomInDuration, zoomOutDuration: zoomOutDuration))
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
        if let zi = o.zoomInDuration { out[o.index].zoomInDuration = zi }
        if let zo = o.zoomOutDuration { out[o.index].zoomOutDuration = zo }
    }
    return out
}
