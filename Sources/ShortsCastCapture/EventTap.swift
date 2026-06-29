// Sources/ShortsCastCapture/EventTap.swift
import Foundation
import CoreGraphics
import ShortsCastCore

/// Listen-only CGEventTap that converts CGEvents into RawInputEvents and feeds a
/// handler. Runs its own run loop on a background thread. The handler is invoked
/// on that thread.
public final class EventTap {
    private let handler: (RawInputEvent) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?

    public init(handler: @escaping (RawInputEvent) -> Void) {
        self.handler = handler
    }

    private static let eventMask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue) |
        (1 << CGEventType.rightMouseDown.rawValue) |
        (1 << CGEventType.otherMouseDown.rawValue) |
        (1 << CGEventType.scrollWheel.rawValue) |
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.mouseMoved.rawValue)

    public func start() {
        let t = Thread { [weak self] in
            guard let self = self else { return }
            let callback: CGEventTapCallBack = { _, type, event, refcon in
                let me = Unmanaged<EventTap>.fromOpaque(refcon!).takeUnretainedValue()
                me.dispatch(type: type, event: event)
                return Unmanaged.passUnretained(event)
            }
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: EventTap.eventMask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else { return }
            self.tap = tap
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        t.start()
        thread = t
    }

    public func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func dispatch(type: CGEventType, event: CGEvent) {
        let t = machNowSeconds()
        let loc = event.location // global points, top-left origin
        switch type {
        case .leftMouseDown:
            handler(RawInputEvent(t: t, kind: .mouseDown, globalPoint: loc, button: .left))
        case .rightMouseDown:
            handler(RawInputEvent(t: t, kind: .mouseDown, globalPoint: loc, button: .right))
        case .otherMouseDown:
            handler(RawInputEvent(t: t, kind: .mouseDown, globalPoint: loc, button: .other))
        case .scrollWheel:
            let dy = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            handler(RawInputEvent(t: t, kind: .scroll, globalPoint: loc, scrollDeltaY: dy))
        case .keyDown:
            handler(RawInputEvent(t: t, kind: .key)) // time only — no keycode
        case .mouseMoved:
            handler(RawInputEvent(t: t, kind: .cursorMove, globalPoint: loc))
        default:
            break
        }
    }
}
