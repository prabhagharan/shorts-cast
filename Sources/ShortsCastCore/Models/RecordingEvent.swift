import Foundation
import CoreGraphics

public enum MouseButton: String, Codable { case left, right, other }

public enum EventType: String, Codable { case click, key, scroll, cursor }

/// One timestamped event from a recording. `point` is nil for key events.
public struct RecordingEvent: Codable, Equatable {
    public var t: Seconds
    public var type: EventType
    public var point: CGPoint?
    public var button: MouseButton?
    public var deltaY: Double?

    public init(t: Seconds, type: EventType, point: CGPoint? = nil,
                button: MouseButton? = nil, deltaY: Double? = nil) {
        self.t = t; self.type = type; self.point = point
        self.button = button; self.deltaY = deltaY
    }

    public static func click(t: Seconds, point: CGPoint, button: MouseButton) -> RecordingEvent {
        RecordingEvent(t: t, type: .click, point: point, button: button)
    }
    public static func key(t: Seconds) -> RecordingEvent {
        RecordingEvent(t: t, type: .key)
    }
    public static func scroll(t: Seconds, point: CGPoint, deltaY: Double) -> RecordingEvent {
        RecordingEvent(t: t, type: .scroll, point: point, deltaY: deltaY)
    }
    public static func cursor(t: Seconds, point: CGPoint) -> RecordingEvent {
        RecordingEvent(t: t, type: .cursor, point: point)
    }
}
