import Foundation
import CoreGraphics

/// A click moment to render as an animated ripple.
public struct ClickRipple: Equatable {
    public var t: Seconds
    public var point: CGPoint
    public init(t: Seconds, point: CGPoint) { self.t = t; self.point = point }
}

/// Smoothed cursor positions plus click ripples, ready for the compositor to draw.
public struct CursorTrack: Equatable {
    public var samples: [TimedPoint]
    public var clicks: [ClickRipple]
    public init(samples: [TimedPoint], clicks: [ClickRipple]) {
        self.samples = samples; self.clicks = clicks
    }
}

public struct CursorTrackBuilder {
    public var smoother: SpringSmoother
    public init(smoother: SpringSmoother) { self.smoother = smoother }

    public func build(from log: EventLog) -> CursorTrack {
        let raw = log.events
            .filter { $0.type == .cursor }
            .compactMap { e -> TimedPoint? in e.point.map { TimedPoint(t: e.t, p: $0) } }
            .sorted { $0.t < $1.t }
        let smoothed = smoother.smooth(raw)

        let clicks = log.events
            .filter { $0.type == .click }
            .compactMap { e -> ClickRipple? in e.point.map { ClickRipple(t: e.t, point: $0) } }
            .sorted { $0.t < $1.t }

        return CursorTrack(samples: smoothed, clicks: clicks)
    }
}
