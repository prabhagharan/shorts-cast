// Sources/ShortsCastCapture/EventLogBuilder.swift
import Foundation
import CoreGraphics
import ShortsCastCore

/// Accumulates mapped events (absolute monotonic seconds), throttles cursor
/// samples, then emits an EventLog rebased so t=0 is the first video frame.
/// Intended to be fed from a single thread (the event-tap thread).
public final class EventLogBuilder {
    public let geometry: CaptureGeometry
    public let cursorInterval: Double
    private var events: [RecordingEvent] = []
    private var lastCursorT: Double?

    public init(geometry: CaptureGeometry, cursorHz: Double = 60) {
        self.geometry = geometry
        self.cursorInterval = cursorHz > 0 ? 1.0 / cursorHz : 0
    }

    public func add(_ raw: RawInputEvent) {
        guard let mapped = EventMapper.map(raw, geometry: geometry) else { return }
        if mapped.type == .cursor {
            if let last = lastCursorT, raw.t - last < cursorInterval { return }
            lastCursorT = raw.t
        }
        events.append(mapped)
    }

    public func build(firstFrameT: Double, endT: Double) -> EventLog {
        let rebased: [RecordingEvent] = events.compactMap { e in
            let t = e.t - firstFrameT
            guard t >= 0 else { return nil }
            var copy = e
            copy.t = t
            return copy
        }.sorted { $0.t < $1.t }
        return EventLog(duration: max(endT - firstFrameT, 0),
                        screenSize: geometry.pixelSize,
                        events: rebased)
    }
}
