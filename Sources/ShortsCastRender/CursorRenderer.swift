import Foundation
import CoreGraphics
import ShortsCastCore

public struct RippleState: Equatable {
    public var point: CGPoint
    public var progress: Double
    public init(point: CGPoint, progress: Double) { self.point = point; self.progress = progress }
}

public enum CursorRenderer {
    /// Interpolated cursor position (source pixel space) at time t; nil if no samples.
    public static func position(at t: Seconds, samples: [TimedPoint]) -> CGPoint? {
        guard let first = samples.first else { return nil }
        if t <= first.t { return first.p }
        guard let last = samples.last, t < last.t else { return samples.last?.p }
        for i in 1..<samples.count where samples[i].t >= t {
            let a = samples[i - 1], b = samples[i]
            let span = b.t - a.t
            let u = span > 0 ? (t - a.t) / span : 0
            return CGPoint(x: a.p.x + (b.p.x - a.p.x) * CGFloat(u),
                           y: a.p.y + (b.p.y - a.p.y) * CGFloat(u))
        }
        return last.p
    }

    /// Ripples currently animating at time t, with progress in [0,1].
    public static func activeRipples(at t: Seconds, clicks: [ClickRipple], duration: Double) -> [RippleState] {
        guard duration > 0 else { return [] }
        return clicks.compactMap { c in
            let dt = t - c.t
            guard dt >= 0, dt <= duration else { return nil }
            return RippleState(point: c.point, progress: dt / duration)
        }
    }
}
