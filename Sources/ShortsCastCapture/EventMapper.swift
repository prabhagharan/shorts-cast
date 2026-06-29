import Foundation
import CoreGraphics
import ShortsCastCore

/// Pure mapping from a RawInputEvent (+ geometry) to a core RecordingEvent.
/// Located events outside the capture area return nil; key events are always kept.
public enum EventMapper {
    public static func map(_ raw: RawInputEvent, geometry: CaptureGeometry) -> RecordingEvent? {
        switch raw.kind {
        case .key:
            return RecordingEvent.key(t: raw.t)
        case .mouseDown:
            guard let g = raw.globalPoint, let p = geometry.mapToPixels(g),
                  let b = raw.button else { return nil }
            return RecordingEvent.click(t: raw.t, point: p, button: b)
        case .scroll:
            guard let g = raw.globalPoint, let p = geometry.mapToPixels(g) else { return nil }
            return RecordingEvent.scroll(t: raw.t, point: p, deltaY: raw.scrollDeltaY ?? 0)
        case .cursorMove:
            guard let g = raw.globalPoint, let p = geometry.mapToPixels(g) else { return nil }
            return RecordingEvent.cursor(t: raw.t, point: p)
        }
    }
}
