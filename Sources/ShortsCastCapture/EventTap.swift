import Foundation
import CoreGraphics
import ShortsCastCore

/// Listen-only CGEventTap that converts CGEvents into RawInputEvents and feeds a
/// handler. Runs its own run loop on a background thread. `stop()` blocks until
/// that thread has fully drained and exited, so a caller may safely read state
/// the handler mutated (e.g. an EventLogBuilder) immediately after stop() returns.
public final class EventTap {
    private let handler: (RawInputEvent) -> Void
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private let finished = DispatchSemaphore(value: 0)

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
        guard thread == nil else { return }
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
            ) else {
                self.finished.signal() // never let stop() block if the tap failed to create
                return
            }
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.lock.lock()
            self.tap = tap
            self.runLoopSource = src
            self.runLoop = CFRunLoopGetCurrent()
            self.lock.unlock()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
            // Run loop stopped: tear down on this same thread, then signal completion.
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
            CFMachPortInvalidate(tap)
            self.finished.signal()
        }
        t.start()
        thread = t
    }

    /// Stops the tap and blocks until the tap thread has exited.
    public func stop() {
        lock.lock()
        let runLoop = self.runLoop
        let tap = self.tap
        lock.unlock()
        guard let runLoop = runLoop else { return } // never started, or already stopped
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        CFRunLoopStop(runLoop)
        finished.wait() // happens-before: all handler/add() calls complete before we return
        lock.lock()
        self.tap = nil
        self.runLoop = nil
        self.runLoopSource = nil
        self.thread = nil
        lock.unlock()
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
