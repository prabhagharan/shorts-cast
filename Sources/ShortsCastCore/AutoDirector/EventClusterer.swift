import Foundation
import CoreGraphics

/// Groups triggering events into FocusSegments in time + space.
public struct EventClusterer {
    public var settings: AutoDirectorSettings
    public init(settings: AutoDirectorSettings) { self.settings = settings }

    private func weight(_ e: RecordingEvent) -> Double {
        switch e.type {
        case .click: return settings.clickWeight
        case .key: return settings.keyWeight
        case .scroll: return settings.scrollWeight
        case .cursor: return 0
        }
    }

    /// Weighted centroid over events that carry a point; nil if none do.
    private func centroid(_ evs: [RecordingEvent]) -> CGPoint? {
        var sx = 0.0, sy = 0.0, sw = 0.0
        for e in evs {
            guard let p = e.point else { continue }
            let w = max(weight(e), 0.0001)
            sx += Double(p.x) * w; sy += Double(p.y) * w; sw += w
        }
        guard sw > 0 else { return nil }
        return CGPoint(x: sx / sw, y: sy / sw)
    }

    public func segments(from log: EventLog) -> [FocusSegment] {
        let triggers = log.events
            .filter { $0.type != .cursor }
            .sorted { $0.t < $1.t }
        guard !triggers.isEmpty else { return [] }

        var result: [FocusSegment] = []
        var current: [RecordingEvent] = []

        func flush() {
            guard let f = current.first, let l = current.last,
                  let c = centroid(current) else { current = []; return }
            var zoom = settings.defaultZoom
            if current.count >= settings.denseEventCount { zoom += settings.denseZoomBonus }
            zoom = min(zoom, settings.maxZoom)
            result.append(FocusSegment(start: f.t, end: l.t, center: c, zoom: zoom))
            current = []
        }

        for e in triggers {
            if current.isEmpty { current = [e]; continue }
            let last = current.last!
            let withinTime = (e.t - last.t) <= settings.clusterTimeGap
            let running = centroid(current)
            let withinSpace: Bool = {
                guard let p = e.point, let c = running else { return true }
                return hypot(Double(p.x - c.x), Double(p.y - c.y)) <= Double(settings.clusterRadius)
            }()
            if withinTime && withinSpace { current.append(e) }
            else { flush(); current = [e] }
        }
        flush()
        return result
    }
}
