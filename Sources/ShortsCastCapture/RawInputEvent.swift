import Foundation
import CoreGraphics
import ShortsCastCore

public enum RawKind: Equatable { case mouseDown, scroll, key, cursorMove }

/// A backend-agnostic input event captured from the OS, before mapping into the
/// recording's coordinate/event model. `t` is monotonic seconds (absolute).
public struct RawInputEvent: Equatable {
    public var t: Double
    public var kind: RawKind
    public var globalPoint: CGPoint?
    public var button: MouseButton?
    public var scrollDeltaY: Double?
    public init(t: Double, kind: RawKind, globalPoint: CGPoint? = nil,
                button: MouseButton? = nil, scrollDeltaY: Double? = nil) {
        self.t = t; self.kind = kind; self.globalPoint = globalPoint
        self.button = button; self.scrollDeltaY = scrollDeltaY
    }
}
