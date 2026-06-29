// Sources/ShortsCastCore/AutoDirector/DwellDetector.swift
import Foundation
import CoreGraphics

/// Detects periods where the cursor lingers in one area and turns them into
/// gentle-zoom focus segments. Complements click/scroll/key clustering.
public struct DwellDetector {
    public var settings: AutoDirectorSettings
    public init(settings: AutoDirectorSettings) { self.settings = settings }

    public func segments(from log: EventLog) -> [FocusSegment] {
        let cursor: [(t: Seconds, p: CGPoint)] = log.events
            .filter { $0.type == .cursor }
            .compactMap { e in e.point.map { (e.t, $0) } }
            .sorted { $0.t < $1.t }
        guard !cursor.isEmpty else { return [] }

        var result: [FocusSegment] = []
        var runStart = 0

        func flush(endIdx: Int) {
            let start = cursor[runStart].t
            let end = cursor[endIdx].t
            guard end - start >= settings.dwellTime else { return }
            var sx = 0.0, sy = 0.0
            let count = endIdx - runStart + 1
            for k in runStart...endIdx { sx += Double(cursor[k].p.x); sy += Double(cursor[k].p.y) }
            let center = CGPoint(x: sx / Double(count), y: sy / Double(count))
            result.append(FocusSegment(start: start, end: end,
                                       center: center,
                                       zoom: min(settings.dwellZoom, settings.maxZoom)))
        }

        for i in 1..<cursor.count {
            let anchor = cursor[runStart].p
            let p = cursor[i].p
            if hypot(Double(p.x - anchor.x), Double(p.y - anchor.y)) <= Double(settings.dwellRadius) {
                continue            // still near the anchor — extend the run
            }
            flush(endIdx: i - 1)    // run broke — emit it if long enough
            runStart = i
        }
        flush(endIdx: cursor.count - 1)
        return result
    }
}

/// Returns `primary` plus any `secondary` segments that do not time-overlap a
/// primary one, sorted by start time. Used to fold gentle dwell zooms in
/// around the stronger click/scroll/key clusters without double-zooming.
public func mergeNonOverlapping(primary: [FocusSegment],
                                secondary: [FocusSegment]) -> [FocusSegment] {
    func overlaps(_ a: FocusSegment, _ b: FocusSegment) -> Bool {
        a.start < b.end && b.start < a.end
    }
    let extra = secondary.filter { s in !primary.contains { overlaps($0, s) } }
    return (primary + extra).sorted { $0.start < $1.start }
}
