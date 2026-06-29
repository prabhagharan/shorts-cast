# ShortsCast Capture & Event Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `ShortsCastCapture` (a reusable capture library) and `shortscast-rec` (a CLI harness) that record a screen video via ScreenCaptureKit plus a synchronized `EventLog` via CGEventTap, and write a `.shortscast` project bundle the existing `ShortsCastCore` `Director` can consume.

**Architecture:** Pure logic (coordinate mapping, event mapping, timestamp rebasing, bundle I/O) is split from thin OS adapters (ScreenCaptureKit, CGEventTap, permissions). Pure units are fully unit-tested; OS adapters are complete code verified by `swift build` plus a final manual run of the CLI on this Mac. All in the same Swift package as `ShortsCastCore`.

**Tech Stack:** Swift 5.7 (Xcode 14.2), Swift Package Manager, XCTest, ScreenCaptureKit, AVFoundation, CoreImage, CoreGraphics, ApplicationServices.

## Global Constraints

- Swift tools version `5.7`; package platform floor stays `.macOS(.v12)`.
- All ScreenCaptureKit code guarded with `@available(macOS 12.3, *)`; CLI errors+exits on macOS < 12.3.
- Event points are mapped into the captured area's pixel space, origin **top-left**; CGEvent locations and `CGDisplayBounds` share that top-left global origin (no Y flip for event mapping).
- `EventLog.screenSize` = captured area pixel size; event timestamps rebased so the first video frame is t=0.
- Cursor samples throttled to **60 Hz**; key events record **time only — no keycodes/characters**.
- Out-of-bounds click/scroll/cursor events are **dropped**; key events always kept.
- Video: H.264, 60 fps cap, native pixel size, `.mov`. No audio.
- Region capture crops frames via CoreImage (because `SCStreamConfiguration.sourceRect` is macOS 14+; this machine is 12.6).
- Pure code never reads a wall clock; the created-date string is passed in by the executable.
- Reuses core types verbatim: `EventLog`, `RecordingEvent` (`.click/.key/.scroll/.cursor`), `MouseButton` (`.left/.right/.other`), `Director`.

---

### Task 1: Package targets + scaffolds

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ShortsCastCapture/ShortsCastCapture.swift`
- Create: `Sources/shortscast-rec/main.swift`
- Test: `Tests/ShortsCastCaptureTests/ScaffoldTests.swift`

**Interfaces:**
- Consumes: `ShortsCastCore` (existing library product).
- Produces: library product `ShortsCastCapture`, executable `shortscast-rec`, test target `ShortsCastCaptureTests`; marker `ShortsCastCapture.version: String`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCaptureTests/ScaffoldTests.swift
import XCTest
@testable import ShortsCastCapture

final class ScaffoldTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(ShortsCastCapture.version.isEmpty)
    }
}
```

- [ ] **Step 2: Update the package manifest**

```swift
// Package.swift
// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ShortsCast",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "ShortsCastCore", targets: ["ShortsCastCore"]),
        .library(name: "ShortsCastCapture", targets: ["ShortsCastCapture"]),
        .executable(name: "shortscast-rec", targets: ["shortscast-rec"])
    ],
    targets: [
        .target(name: "ShortsCastCore"),
        .testTarget(name: "ShortsCastCoreTests", dependencies: ["ShortsCastCore"]),
        .target(name: "ShortsCastCapture", dependencies: ["ShortsCastCore"]),
        .testTarget(name: "ShortsCastCaptureTests", dependencies: ["ShortsCastCapture"]),
        .executableTarget(name: "shortscast-rec", dependencies: ["ShortsCastCapture", "ShortsCastCore"])
    ]
)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ScaffoldTests`
Expected: FAIL — `ShortsCastCapture` module/target does not exist.

- [ ] **Step 4: Create the marker source and CLI stub**

```swift
// Sources/ShortsCastCapture/ShortsCastCapture.swift
import Foundation

public enum ShortsCastCapture {
    public static let version = "0.1.0"
}
```

```swift
// Sources/shortscast-rec/main.swift
import Foundation
import ShortsCastCapture

// Fleshed out in Task 11. Stub keeps the executable target compiling.
FileHandle.standardError.write(Data("shortscast-rec \(ShortsCastCapture.version)\n".utf8))
```

- [ ] **Step 5: Run test + build to verify both pass**

Run: `swift test --filter ScaffoldTests` then `swift build`
Expected: test PASSES; `swift build` succeeds and produces the `shortscast-rec` executable.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ShortsCastCapture Sources/shortscast-rec Tests/ShortsCastCaptureTests
git commit -m "feat: scaffold ShortsCastCapture library and shortscast-rec CLI"
```

---

### Task 2: CaptureGeometry (pure coordinate mapping)

**Files:**
- Create: `Sources/ShortsCastCapture/CaptureGeometry.swift`
- Test: `Tests/ShortsCastCaptureTests/CaptureGeometryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct CaptureGeometry: Equatable { let captureRect: CGRect; let scale: CGFloat; var pixelSize: CGSize; func mapToPixels(_ global: CGPoint) -> CGPoint? }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCaptureTests/CaptureGeometryTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCapture

final class CaptureGeometryTests: XCTestCase {
    func test_pixelSize_appliesScale() {
        let g = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2)
        XCTAssertEqual(g.pixelSize, CGSize(width: 1600, height: 1200))
    }
    func test_mainDisplay_mapsPointToPixels() {
        let g = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 2)
        XCTAssertEqual(g.mapToPixels(CGPoint(x: 100, y: 50)), CGPoint(x: 200, y: 100))
    }
    func test_offsetDisplay_subtractsOrigin() {
        // a 2x external display arranged to the right of a 1920-wide main display
        let g = CaptureGeometry(captureRect: CGRect(x: 1920, y: 0, width: 1000, height: 1000), scale: 2)
        XCTAssertEqual(g.mapToPixels(CGPoint(x: 1920 + 10, y: 5)), CGPoint(x: 20, y: 10))
    }
    func test_outOfBounds_returnsNil() {
        let g = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        XCTAssertNil(g.mapToPixels(CGPoint(x: -1, y: 5)))
        XCTAssertNil(g.mapToPixels(CGPoint(x: 5, y: 101)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CaptureGeometryTests`
Expected: FAIL — `CaptureGeometry` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCapture/CaptureGeometry.swift
import Foundation
import CoreGraphics

/// Maps global CGEvent points (top-left origin, points) into the captured
/// area's pixel space (top-left origin). CGEvent and CGDisplayBounds share the
/// same top-left global origin, so this is translate-then-scale with no Y flip.
public struct CaptureGeometry: Equatable {
    public let captureRect: CGRect   // global points
    public let scale: CGFloat        // pixels per point

    public init(captureRect: CGRect, scale: CGFloat) {
        self.captureRect = captureRect
        self.scale = scale
    }

    /// Output video pixel dimensions.
    public var pixelSize: CGSize {
        CGSize(width: captureRect.width * scale, height: captureRect.height * scale)
    }

    /// Maps a global point to captured-area pixels, or nil if outside the area.
    public func mapToPixels(_ global: CGPoint) -> CGPoint? {
        let x = (global.x - captureRect.minX) * scale
        let y = (global.y - captureRect.minY) * scale
        let size = pixelSize
        guard x >= 0, y >= 0, x <= size.width, y <= size.height else { return nil }
        return CGPoint(x: x, y: y)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CaptureGeometryTests`
Expected: PASS — all four cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCapture/CaptureGeometry.swift Tests/ShortsCastCaptureTests/CaptureGeometryTests.swift
git commit -m "feat: add CaptureGeometry coordinate mapping"
```

---

### Task 3: RawInputEvent + EventMapper (pure)

**Files:**
- Create: `Sources/ShortsCastCapture/RawInputEvent.swift`
- Create: `Sources/ShortsCastCapture/EventMapper.swift`
- Test: `Tests/ShortsCastCaptureTests/EventMapperTests.swift`

**Interfaces:**
- Consumes: `CaptureGeometry` (Task 2); `RecordingEvent`, `MouseButton` (core).
- Produces:
  - `enum RawKind: Equatable { case mouseDown, scroll, key, cursorMove }`
  - `struct RawInputEvent: Equatable { var t: Double; var kind: RawKind; var globalPoint: CGPoint?; var button: MouseButton?; var scrollDeltaY: Double? }`
  - `enum EventMapper { static func map(_ raw: RawInputEvent, geometry: CaptureGeometry) -> RecordingEvent? }` — returns a `RecordingEvent` with **absolute** `t = raw.t` (rebasing happens later); nil for located events outside the area or a mouseDown with no button.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCaptureTests/EventMapperTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastCapture

final class EventMapperTests: XCTestCase {
    private let geo = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 2)

    func test_mouseDown_mapsToClickInPixels() {
        let raw = RawInputEvent(t: 1.5, kind: .mouseDown, globalPoint: CGPoint(x: 100, y: 50), button: .left)
        let e = EventMapper.map(raw, geometry: geo)
        XCTAssertEqual(e?.type, .click)
        XCTAssertEqual(e?.point, CGPoint(x: 200, y: 100))
        XCTAssertEqual(e?.button, .left)
        XCTAssertEqual(e?.t ?? -1, 1.5, accuracy: 1e-9)
    }
    func test_key_keptWithNoPoint() {
        let e = EventMapper.map(RawInputEvent(t: 2.0, kind: .key), geometry: geo)
        XCTAssertEqual(e?.type, .key)
        XCTAssertNil(e?.point)
    }
    func test_scroll_preservesDeltaSign() {
        let raw = RawInputEvent(t: 3.0, kind: .scroll, globalPoint: CGPoint(x: 10, y: 10), scrollDeltaY: -4)
        let e = EventMapper.map(raw, geometry: geo)
        XCTAssertEqual(e?.type, .scroll)
        XCTAssertEqual(e?.deltaY ?? 0, -4, accuracy: 1e-9)
    }
    func test_outOfBoundsClick_returnsNil() {
        let raw = RawInputEvent(t: 1, kind: .mouseDown, globalPoint: CGPoint(x: 5000, y: 5000), button: .left)
        XCTAssertNil(EventMapper.map(raw, geometry: geo))
    }
    func test_mouseDownWithoutButton_returnsNil() {
        let raw = RawInputEvent(t: 1, kind: .mouseDown, globalPoint: CGPoint(x: 10, y: 10), button: nil)
        XCTAssertNil(EventMapper.map(raw, geometry: geo))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EventMapperTests`
Expected: FAIL — `RawInputEvent` / `EventMapper` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCapture/RawInputEvent.swift
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
```

```swift
// Sources/ShortsCastCapture/EventMapper.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EventMapperTests`
Expected: PASS — all five cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCapture/RawInputEvent.swift Sources/ShortsCastCapture/EventMapper.swift Tests/ShortsCastCaptureTests/EventMapperTests.swift
git commit -m "feat: add RawInputEvent and EventMapper"
```

---

### Task 4: Mach clock conversion

**Files:**
- Create: `Sources/ShortsCastCapture/MachClock.swift`
- Test: `Tests/ShortsCastCaptureTests/MachClockTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `func machTicksToSeconds(_ ticks: UInt64, numer: UInt32, denom: UInt32) -> Double` — pure.
  - `func machNowSeconds() -> Double` — live monotonic clock (reads `mach_timebase_info` + `mach_absolute_time`); used by the OS adapters. Not unit-tested (wraps the pure converter).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCaptureTests/MachClockTests.swift
import XCTest
@testable import ShortsCastCapture

final class MachClockTests: XCTestCase {
    func test_identityTimebase_nanosToSeconds() {
        // numer/denom = 1/1 → ticks are nanoseconds
        XCTAssertEqual(machTicksToSeconds(1_000_000_000, numer: 1, denom: 1), 1.0, accuracy: 1e-12)
    }
    func test_scaledTimebase() {
        // numer/denom = 125/3 (a real Apple-silicon-style ratio): 24,000,000 ticks
        // → 24e6 * 125/3 ns = 1.0e9 ns = 1.0 s
        XCTAssertEqual(machTicksToSeconds(24_000_000, numer: 125, denom: 3), 1.0, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MachClockTests`
Expected: FAIL — `machTicksToSeconds` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCapture/MachClock.swift
import Foundation

/// Converts mach_absolute_time ticks to seconds given the timebase. Pure (testable);
/// the OS layer supplies the real timebase via mach_timebase_info.
public func machTicksToSeconds(_ ticks: UInt64, numer: UInt32, denom: UInt32) -> Double {
    let nanos = Double(ticks) * Double(numer) / Double(denom)
    return nanos / 1_000_000_000.0
}

/// Live monotonic clock in seconds, on the same timeline as ScreenCaptureKit
/// sample presentation timestamps (both derive from the mach host clock).
public func machNowSeconds() -> Double {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return machTicksToSeconds(mach_absolute_time(), numer: info.numer, denom: info.denom)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MachClockTests`
Expected: PASS — both cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCapture/MachClock.swift Tests/ShortsCastCaptureTests/MachClockTests.swift
git commit -m "feat: add mach clock tick-to-seconds conversion"
```

---

### Task 5: EventLogBuilder (pure accumulation, throttle, rebase)

**Files:**
- Create: `Sources/ShortsCastCapture/EventLogBuilder.swift`
- Test: `Tests/ShortsCastCaptureTests/EventLogBuilderTests.swift`

**Interfaces:**
- Consumes: `CaptureGeometry` (Task 2), `RawInputEvent`/`EventMapper` (Task 3), `EventLog`/`RecordingEvent` (core).
- Produces:
  - `final class EventLogBuilder { init(geometry: CaptureGeometry, cursorHz: Double = 60); func add(_ raw: RawInputEvent); func build(firstFrameT: Double, endT: Double) -> EventLog }`
  - `add` maps via `EventMapper`, drops nils, and throttles cursor events to `cursorHz`. `build` rebases by `firstFrameT` (dropping events with rebased `t < 0`), sorts by time, sets `duration = max(endT - firstFrameT, 0)` and `screenSize = geometry.pixelSize`. Single-threaded use (fed from one event-tap thread).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCaptureTests/EventLogBuilderTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastCapture

final class EventLogBuilderTests: XCTestCase {
    private let geo = CaptureGeometry(captureRect: CGRect(x: 0, y: 0, width: 1000, height: 1000), scale: 1)

    func test_cursorThrottle_keepsLatestPerTick() {
        let b = EventLogBuilder(geometry: geo, cursorHz: 60) // interval ~0.01667s
        b.add(RawInputEvent(t: 0.000, kind: .cursorMove, globalPoint: CGPoint(x: 1, y: 1)))   // kept (first)
        b.add(RawInputEvent(t: 0.005, kind: .cursorMove, globalPoint: CGPoint(x: 2, y: 2)))   // dropped (<16.7ms)
        b.add(RawInputEvent(t: 0.020, kind: .cursorMove, globalPoint: CGPoint(x: 3, y: 3)))   // kept
        let log = b.build(firstFrameT: 0, endT: 1)
        XCTAssertEqual(log.events.filter { $0.type == .cursor }.count, 2)
    }

    func test_build_rebasesAndDropsPreStartEvents() {
        let b = EventLogBuilder(geometry: geo, cursorHz: 60)
        b.add(RawInputEvent(t: 1.0, kind: .mouseDown, globalPoint: CGPoint(x: 10, y: 10), button: .left)) // before frame
        b.add(RawInputEvent(t: 3.0, kind: .mouseDown, globalPoint: CGPoint(x: 20, y: 20), button: .left)) // after
        let log = b.build(firstFrameT: 2.0, endT: 5.0)
        XCTAssertEqual(log.events.count, 1)
        XCTAssertEqual(log.events[0].t, 1.0, accuracy: 1e-9) // 3.0 - 2.0
        XCTAssertEqual(log.duration, 3.0, accuracy: 1e-9)
        XCTAssertEqual(log.screenSize, CGSize(width: 1000, height: 1000))
    }

    func test_build_keysAreKeptAndSorted() {
        let b = EventLogBuilder(geometry: geo, cursorHz: 60)
        b.add(RawInputEvent(t: 2.5, kind: .key))
        b.add(RawInputEvent(t: 2.1, kind: .mouseDown, globalPoint: CGPoint(x: 5, y: 5), button: .left))
        let log = b.build(firstFrameT: 2.0, endT: 4.0)
        XCTAssertEqual(log.events.map { $0.type }, [.click, .key]) // sorted by t: 0.1 then 0.5
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EventLogBuilderTests`
Expected: FAIL — `EventLogBuilder` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EventLogBuilderTests`
Expected: PASS — all three cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCapture/EventLogBuilder.swift Tests/ShortsCastCaptureTests/EventLogBuilderTests.swift
git commit -m "feat: add EventLogBuilder with cursor throttle and t=0 rebasing"
```

---

### Task 6: ProjectBundle + BundleMeta (filesystem I/O)

**Files:**
- Create: `Sources/ShortsCastCapture/ProjectBundle.swift`
- Test: `Tests/ShortsCastCaptureTests/ProjectBundleTests.swift`

**Interfaces:**
- Consumes: `EventLog` (core).
- Produces:
  - `struct BundleMeta: Codable, Equatable { var targetKind: String; var displayID: UInt32?; var scale: Double; var captureRect: CGRect; var appVersion: String; var created: String }`
  - `enum ProjectBundle { static func write(eventLog:meta:rawVideo:to:) throws; static func read(_:) throws -> (eventLog: EventLog, meta: BundleMeta, rawVideoURL: URL) }`
  - `write` creates the `.shortscast` folder, copies `rawVideo` → `raw.mov`, encodes `events.json` and `meta.json`. Throws `BundleError.rawVideoMissing` if the source is absent.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCaptureTests/ProjectBundleTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastCapture

final class ProjectBundleTests: XCTestCase {
    func test_writeThenRead_roundTrips() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scbundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // a stand-in "raw video" file
        let fakeMov = tmp.appendingPathComponent("src.mov")
        try Data("not really a movie".utf8).write(to: fakeMov)

        let log = EventLog(duration: 4, screenSize: CGSize(width: 1920, height: 1080),
                           events: [.click(t: 1, point: CGPoint(x: 10, y: 20), button: .left)])
        let meta = BundleMeta(targetKind: "display", displayID: 1, scale: 2,
                              captureRect: CGRect(x: 0, y: 0, width: 960, height: 540),
                              appVersion: "0.1.0", created: "2026-06-29T00:00:00Z")

        let bundle = tmp.appendingPathComponent("out.shortscast")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: fakeMov, to: bundle)

        let read = try ProjectBundle.read(bundle)
        XCTAssertEqual(read.eventLog, log)
        XCTAssertEqual(read.meta, meta)
        XCTAssertTrue(FileManager.default.fileExists(atPath: read.rawVideoURL.path))
    }

    func test_write_missingRawVideo_throws() {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("x.shortscast")
        let log = EventLog(duration: 0, screenSize: .zero, events: [])
        let meta = BundleMeta(targetKind: "display", displayID: nil, scale: 1,
                              captureRect: .zero, appVersion: "0", created: "t")
        XCTAssertThrowsError(try ProjectBundle.write(
            eventLog: log, meta: meta,
            rawVideo: URL(fileURLWithPath: "/no/such/file.mov"), to: bundle))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectBundleTests`
Expected: FAIL — `ProjectBundle` / `BundleMeta` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCapture/ProjectBundle.swift
import Foundation
import CoreGraphics
import ShortsCastCore

public struct BundleMeta: Codable, Equatable {
    public var targetKind: String      // "display" | "window" | "region"
    public var displayID: UInt32?
    public var scale: Double
    public var captureRect: CGRect     // global points
    public var appVersion: String
    public var created: String         // ISO8601, supplied by the caller
    public init(targetKind: String, displayID: UInt32?, scale: Double,
                captureRect: CGRect, appVersion: String, created: String) {
        self.targetKind = targetKind; self.displayID = displayID; self.scale = scale
        self.captureRect = captureRect; self.appVersion = appVersion; self.created = created
    }
}

public enum ProjectBundle {
    public enum BundleError: Error { case rawVideoMissing }

    public static func write(eventLog: EventLog, meta: BundleMeta,
                             rawVideo: URL, to bundleURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rawVideo.path) else { throw BundleError.rawVideoMissing }
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try fm.copyItem(at: rawVideo, to: bundleURL.appendingPathComponent("raw.mov"))
        let enc = JSONEncoder()
        try enc.encode(eventLog).write(to: bundleURL.appendingPathComponent("events.json"))
        try enc.encode(meta).write(to: bundleURL.appendingPathComponent("meta.json"))
    }

    public static func read(_ bundleURL: URL) throws
        -> (eventLog: EventLog, meta: BundleMeta, rawVideoURL: URL) {
        let dec = JSONDecoder()
        let log = try dec.decode(EventLog.self,
            from: Data(contentsOf: bundleURL.appendingPathComponent("events.json")))
        let meta = try dec.decode(BundleMeta.self,
            from: Data(contentsOf: bundleURL.appendingPathComponent("meta.json")))
        return (log, meta, bundleURL.appendingPathComponent("raw.mov"))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProjectBundleTests`
Expected: PASS — both cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCapture/ProjectBundle.swift Tests/ShortsCastCaptureTests/ProjectBundleTests.swift
git commit -m "feat: add ProjectBundle read/write and BundleMeta"
```

---

### Task 7: Permissions

**Files:**
- Create: `Sources/ShortsCastCapture/Permissions.swift`
- Test: `Tests/ShortsCastCaptureTests/PermissionsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum Permissions { struct Status: Equatable { var screenRecording: Bool; var accessibility: Bool; var allGranted: Bool }; static func status() -> Status; static func request() }`
  - Only the pure `Status.allGranted` logic is unit-tested; `status()`/`request()` call OS APIs and are verified by the manual run (Task 12).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCaptureTests/PermissionsTests.swift
import XCTest
@testable import ShortsCastCapture

final class PermissionsTests: XCTestCase {
    func test_allGranted_trueOnlyWhenBoth() {
        XCTAssertTrue(Permissions.Status(screenRecording: true, accessibility: true).allGranted)
        XCTAssertFalse(Permissions.Status(screenRecording: true, accessibility: false).allGranted)
        XCTAssertFalse(Permissions.Status(screenRecording: false, accessibility: true).allGranted)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PermissionsTests`
Expected: FAIL — `Permissions` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCapture/Permissions.swift
import Foundation
import CoreGraphics
import ApplicationServices

public enum Permissions {
    public struct Status: Equatable {
        public var screenRecording: Bool
        public var accessibility: Bool
        public init(screenRecording: Bool, accessibility: Bool) {
            self.screenRecording = screenRecording
            self.accessibility = accessibility
        }
        public var allGranted: Bool { screenRecording && accessibility }
    }

    public static func status() -> Status {
        Status(screenRecording: CGPreflightScreenCaptureAccess(),
               accessibility: AXIsProcessTrusted())
    }

    /// Prompts for any missing permission (no-ops if already granted).
    public static func request() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }
}
```

- [ ] **Step 4: Run test + build to verify**

Run: `swift test --filter PermissionsTests` then `swift build`
Expected: test PASSES; build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCapture/Permissions.swift Tests/ShortsCastCaptureTests/PermissionsTests.swift
git commit -m "feat: add screen-recording + accessibility permission checks"
```

---

### Task 8: ScreenCaptureSession (ScreenCaptureKit → AVAssetWriter)

**Files:**
- Create: `Sources/ShortsCastCapture/ScreenCaptureSession.swift`

**Interfaces:**
- Consumes: `machNowSeconds()` (Task 4).
- Produces: `@available(macOS 12.3, *) final class ScreenCaptureSession: NSObject, SCStreamOutput` with
  - `init(outputURL: URL, pixelSize: CGSize, cropRectPixels: CGRect?)`
  - `func start(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws`
  - `func stop() async -> (firstFrameT: Double, endT: Double)`
  - `var firstFramePTSSeconds: Double?`
- OS-bound: verified by `swift build` here and the manual run (Task 12). `cropRectPixels` (region) crops each frame via CoreImage; nil means write frames as-is.

- [ ] **Step 1: Write the implementation**

```swift
// Sources/ShortsCastCapture/ScreenCaptureSession.swift
import Foundation
import AVFoundation
import CoreMedia
import CoreImage
import CoreVideo
import ScreenCaptureKit
import CoreGraphics

@available(macOS 12.3, *)
public final class ScreenCaptureSession: NSObject, SCStreamOutput {
    public enum CaptureError: Error { case writerSetupFailed }

    private let outputURL: URL
    private let pixelSize: CGSize
    private let cropRectPixels: CGRect?
    private let ciContext = CIContext()
    private let sampleQueue = DispatchQueue(label: "shortscast.capture.samples")

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    public private(set) var firstFramePTSSeconds: Double?

    public init(outputURL: URL, pixelSize: CGSize, cropRectPixels: CGRect?) {
        self.outputURL = outputURL
        self.pixelSize = pixelSize
        self.cropRectPixels = cropRectPixels
    }

    private func makeWriter() throws {
        let w = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixelSize.width),
            AVVideoHeightKey: Int(pixelSize.height)
        ]
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        i.expectsMediaDataInRealTime = true
        let a = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: i, sourcePixelBufferAttributes: nil)
        guard w.canAdd(i) else { throw CaptureError.writerSetupFailed }
        w.add(i)
        writer = w; input = i; adaptor = a
    }

    public func start(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws {
        try makeWriter()
        let s = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        stream = s
        try await s.startCapture()
    }

    public func stop() async -> (firstFrameT: Double, endT: Double) {
        if let s = stream { try? await s.stopCapture() }
        let end = machNowSeconds()
        input?.markAsFinished()
        if let w = writer { await w.finishWriting() }
        return (firstFramePTSSeconds ?? end, end)
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let writer = writer, let input = input, let adaptor = adaptor,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            firstFramePTSSeconds = CMTimeGetSeconds(pts)
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }

        if let crop = cropRectPixels {
            guard let cropped = cropPixelBuffer(imageBuffer, to: crop) else { return }
            adaptor.append(cropped, withPresentationTime: pts)
        } else {
            adaptor.append(imageBuffer, withPresentationTime: pts)
        }
    }

    /// Crops a frame to `rect` (top-left pixel coords) into a new BGRA pixel buffer.
    private func cropPixelBuffer(_ src: CVPixelBuffer, to rect: CGRect) -> CVPixelBuffer? {
        let ci = CIImage(cvPixelBuffer: src)
        let h = CGFloat(CVPixelBufferGetHeight(src))
        // CIImage origin is bottom-left; flip the top-left rect into CI space.
        let ciRect = CGRect(x: rect.minX, y: h - rect.maxY, width: rect.width, height: rect.height)
        let cropped = ci.cropped(to: ciRect)
            .transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY))
        var out: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, Int(rect.width), Int(rect.height),
                            kCVPixelFormatType_32BGRA, attrs, &out)
        guard let dst = out else { return nil }
        ciContext.render(cropped, to: dst)
        return dst
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: succeeds with no errors (warnings about availability are acceptable only if none appear; the `@available` annotation should silence them).

- [ ] **Step 3: Commit**

```bash
git add Sources/ShortsCastCapture/ScreenCaptureSession.swift
git commit -m "feat: add ScreenCaptureKit capture session with region crop"
```

---

### Task 9: EventTap (CGEventTap adapter)

**Files:**
- Create: `Sources/ShortsCastCapture/EventTap.swift`

**Interfaces:**
- Consumes: `RawInputEvent`/`RawKind` (Task 3), `machNowSeconds()` (Task 4), `MouseButton` (core).
- Produces: `final class EventTap { init(handler: @escaping (RawInputEvent) -> Void); func start(); func stop() }` — a listen-only `CGEventTap` on a dedicated run-loop thread that emits `RawInputEvent`s. OS-bound: verified by `swift build` and the manual run.

- [ ] **Step 1: Write the implementation**

```swift
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShortsCastCapture/EventTap.swift
git commit -m "feat: add listen-only CGEventTap adapter"
```

---

### Task 10: Target resolution + Recorder facade

**Files:**
- Create: `Sources/ShortsCastCapture/TargetResolver.swift`
- Create: `Sources/ShortsCastCapture/Recorder.swift`

**Interfaces:**
- Consumes: everything above — `CaptureGeometry`, `EventLogBuilder`, `EventTap`, `ScreenCaptureSession`, `ProjectBundle`/`BundleMeta`, `machNowSeconds()`; `EventLog` (core).
- Produces:
  - `@available(macOS 12.3, *) struct ResolvedTarget { kind: String; displayID: UInt32?; captureRectPoints: CGRect; scale: CGFloat; cropPixels: CGRect?; filter: SCContentFilter; configuration: SCStreamConfiguration }`
  - `@available(macOS 12.3, *) enum TargetResolver { static func resolve(displayIndex: Int?, windowQuery: String?, region: CGRect?) async throws -> ResolvedTarget }`
  - `@available(macOS 12.3, *) enum Recorder { struct Result { let bundleURL: URL; let eventLog: EventLog }; static func record(target: ResolvedTarget, seconds: Double, outBundle: URL, appVersion: String, createdISO: String) async throws -> Result }`
- OS-bound: verified by `swift build` and the manual run.

- [ ] **Step 1: Write the target resolver**

```swift
// Sources/ShortsCastCapture/TargetResolver.swift
import Foundation
import CoreGraphics
import ScreenCaptureKit

@available(macOS 12.3, *)
public struct ResolvedTarget {
    public let kind: String
    public let displayID: UInt32?
    public let captureRectPoints: CGRect
    public let scale: CGFloat
    public let cropPixels: CGRect?
    public let filter: SCContentFilter
    public let configuration: SCStreamConfiguration
}

@available(macOS 12.3, *)
public enum TargetResolver {
    public enum ResolveError: Error { case noDisplay, noWindow, badRegion }

    private static func shareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { cont in
            SCShareableContent.getWithCompletionHandler { content, error in
                if let content = content { cont.resume(returning: content) }
                else { cont.resume(throwing: error ?? ResolveError.noDisplay) }
            }
        }
    }

    private static func scale(for displayID: CGDirectDisplayID, pointWidth: CGFloat) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), pointWidth > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / pointWidth
    }

    private static func config(pixelWidth: Int, pixelHeight: Int) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.width = pixelWidth
        c.height = pixelHeight
        c.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.queueDepth = 6
        return c
    }

    public static func resolve(displayIndex: Int?, windowQuery: String?, region: CGRect?) async throws -> ResolvedTarget {
        let content = try await shareableContent()

        // WINDOW
        if let query = windowQuery {
            guard let win = content.windows.first(where: { w in
                (w.owningApplication?.applicationName.localizedCaseInsensitiveContains(query) ?? false)
                || String(w.windowID) == query
            }) else { throw ResolveError.noWindow }
            let rect = win.frame
            let displayID = content.displays.first(where: { $0.frame.intersects(rect) })?.displayID
                ?? CGMainDisplayID()
            let s = scale(for: displayID, pointWidth: content.displays.first(where: { $0.displayID == displayID })?.frame.width ?? rect.width)
            let filter = SCContentFilter(desktopIndependentWindow: win)
            let cfg = config(pixelWidth: Int(rect.width * s), pixelHeight: Int(rect.height * s))
            return ResolvedTarget(kind: "window", displayID: displayID, captureRectPoints: rect,
                                  scale: s, cropPixels: nil, filter: filter, configuration: cfg)
        }

        // pick display (index into content.displays, default main)
        let display: SCDisplay
        if let idx = displayIndex {
            guard idx >= 0, idx < content.displays.count else { throw ResolveError.noDisplay }
            display = content.displays[idx]
        } else {
            guard let main = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else { throw ResolveError.noDisplay }
            display = main
        }
        let dRect = display.frame
        let s = scale(for: display.displayID, pointWidth: dRect.width)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        // REGION (crop the full-display capture to the region in pixels)
        if let region = region {
            guard dRect.contains(region) else { throw ResolveError.badRegion }
            let cfg = config(pixelWidth: Int(dRect.width * s), pixelHeight: Int(dRect.height * s))
            let cropPixels = CGRect(x: (region.minX - dRect.minX) * s,
                                    y: (region.minY - dRect.minY) * s,
                                    width: region.width * s, height: region.height * s)
            return ResolvedTarget(kind: "region", displayID: display.displayID,
                                  captureRectPoints: region, scale: s, cropPixels: cropPixels,
                                  filter: filter, configuration: cfg)
        }

        // FULL DISPLAY
        let cfg = config(pixelWidth: Int(dRect.width * s), pixelHeight: Int(dRect.height * s))
        return ResolvedTarget(kind: "display", displayID: display.displayID,
                              captureRectPoints: dRect, scale: s, cropPixels: nil,
                              filter: filter, configuration: cfg)
    }
}
```

- [ ] **Step 2: Write the Recorder facade**

```swift
// Sources/ShortsCastCapture/Recorder.swift
import Foundation
import CoreGraphics
import ShortsCastCore

@available(macOS 12.3, *)
public enum Recorder {
    public struct Result {
        public let bundleURL: URL
        public let eventLog: EventLog
    }

    /// Records `seconds` of the resolved target and writes a `.shortscast` bundle.
    public static func record(target: ResolvedTarget, seconds: Double, outBundle: URL,
                              appVersion: String, createdISO: String) async throws -> Result {
        let geometry = CaptureGeometry(captureRect: target.captureRectPoints, scale: target.scale)
        let builder = EventLogBuilder(geometry: geometry, cursorHz: 60)
        let tap = EventTap { builder.add($0) }
        tap.start()

        let tmpMov = FileManager.default.temporaryDirectory
            .appendingPathComponent("shortscast-\(UUID().uuidString).mov")
        let session = ScreenCaptureSession(outputURL: tmpMov,
                                           pixelSize: geometry.pixelSize,
                                           cropRectPixels: target.cropPixels)
        try await session.start(filter: target.filter, configuration: target.configuration)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        let times = await session.stop()
        tap.stop()

        let log = builder.build(firstFrameT: times.firstFrameT, endT: times.endT)
        let meta = BundleMeta(targetKind: target.kind, displayID: target.displayID,
                              scale: Double(target.scale), captureRect: target.captureRectPoints,
                              appVersion: appVersion, created: createdISO)
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: tmpMov, to: outBundle)
        try? FileManager.default.removeItem(at: tmpMov)
        return Result(bundleURL: outBundle, eventLog: log)
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/ShortsCastCapture/TargetResolver.swift Sources/ShortsCastCapture/Recorder.swift
git commit -m "feat: add target resolution and Recorder facade"
```

---

### Task 11: CLI option parsing + main wiring

**Files:**
- Create: `Sources/ShortsCastCapture/CLIOptions.swift`
- Modify: `Sources/shortscast-rec/main.swift`
- Test: `Tests/ShortsCastCaptureTests/CLIOptionsTests.swift`

**Interfaces:**
- Consumes: nothing (pure parser); the executable wires it to `Permissions`, `TargetResolver`, `Recorder`, and `Director`.
- Produces:
  - `struct CLIOptions: Equatable { var seconds: Double; var out: String; var displayIndex: Int?; var windowQuery: String?; var region: CGRect?; var runDirect: Bool }`
  - `enum CLIParseError: Error, Equatable { case missingRequired(String); case badValue(String); case conflictingTargets }`
  - `enum CLIOptions { ... }` → actually `extension CLIOptions { static func parse(_ args: [String]) throws -> CLIOptions }` — parses the flags from the spec; exactly one of `--display/--window/--rect` (or none → main display); `--seconds` and `--out` required.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCaptureTests/CLIOptionsTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCapture

final class CLIOptionsTests: XCTestCase {
    func test_parse_minimal_defaultsToMainDisplay() throws {
        let o = try CLIOptions.parse(["--seconds", "5", "--out", "a.shortscast"])
        XCTAssertEqual(o.seconds, 5, accuracy: 1e-9)
        XCTAssertEqual(o.out, "a.shortscast")
        XCTAssertNil(o.displayIndex); XCTAssertNil(o.windowQuery); XCTAssertNil(o.region)
        XCTAssertFalse(o.runDirect)
    }
    func test_parse_region_and_direct() throws {
        let o = try CLIOptions.parse(["--seconds", "3", "--out", "x", "--rect", "10,20,640,480", "--direct"])
        XCTAssertEqual(o.region, CGRect(x: 10, y: 20, width: 640, height: 480))
        XCTAssertTrue(o.runDirect)
    }
    func test_parse_missingSeconds_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(["--out", "x"])) { err in
            XCTAssertEqual(err as? CLIParseError, .missingRequired("--seconds"))
        }
    }
    func test_parse_conflictingTargets_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(
            ["--seconds", "1", "--out", "x", "--display", "0", "--window", "Safari"])) { err in
            XCTAssertEqual(err as? CLIParseError, .conflictingTargets)
        }
    }
    func test_parse_badRect_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(["--seconds", "1", "--out", "x", "--rect", "1,2,3"])) { err in
            XCTAssertEqual(err as? CLIParseError, .badValue("--rect"))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CLIOptionsTests`
Expected: FAIL — `CLIOptions` not defined.

- [ ] **Step 3: Write the parser**

```swift
// Sources/ShortsCastCapture/CLIOptions.swift
import Foundation
import CoreGraphics

public enum CLIParseError: Error, Equatable {
    case missingRequired(String)
    case badValue(String)
    case conflictingTargets
}

public struct CLIOptions: Equatable {
    public var seconds: Double
    public var out: String
    public var displayIndex: Int?
    public var windowQuery: String?
    public var region: CGRect?
    public var runDirect: Bool

    public static func parse(_ args: [String]) throws -> CLIOptions {
        var seconds: Double?
        var out: String?
        var displayIndex: Int?
        var windowQuery: String?
        var region: CGRect?
        var runDirect = false

        var i = 0
        func nextValue(_ flag: String) throws -> String {
            i += 1
            guard i < args.count else { throw CLIParseError.badValue(flag) }
            return args[i]
        }

        while i < args.count {
            let a = args[i]
            switch a {
            case "--seconds":
                guard let v = Double(try nextValue(a)) else { throw CLIParseError.badValue(a) }
                seconds = v
            case "--out":
                out = try nextValue(a)
            case "--display":
                guard let v = Int(try nextValue(a)) else { throw CLIParseError.badValue(a) }
                displayIndex = v
            case "--window":
                windowQuery = try nextValue(a)
            case "--rect":
                let parts = try nextValue(a).split(separator: ",").map { Double($0) }
                guard parts.count == 4, !parts.contains(where: { $0 == nil }) else {
                    throw CLIParseError.badValue(a)
                }
                region = CGRect(x: parts[0]!, y: parts[1]!, width: parts[2]!, height: parts[3]!)
            case "--direct":
                runDirect = true
            default:
                throw CLIParseError.badValue(a)
            }
            i += 1
        }

        let targetCount = [displayIndex != nil, windowQuery != nil, region != nil].filter { $0 }.count
        if targetCount > 1 { throw CLIParseError.conflictingTargets }
        guard let s = seconds else { throw CLIParseError.missingRequired("--seconds") }
        guard let o = out else { throw CLIParseError.missingRequired("--out") }

        return CLIOptions(seconds: s, out: o, displayIndex: displayIndex,
                          windowQuery: windowQuery, region: region, runDirect: runDirect)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CLIOptionsTests`
Expected: PASS — all five cases.

- [ ] **Step 5: Write the executable main**

```swift
// Sources/shortscast-rec/main.swift
import Foundation
import CoreGraphics
import ShortsCastCapture
import ShortsCastCore

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard #available(macOS 12.3, *) else {
    fail("shortscast-rec requires macOS 12.3 or later (ScreenCaptureKit).")
}

let options: CLIOptions
do {
    options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("""
    Usage: shortscast-rec --seconds N --out path.shortscast \
    [--display N | --window <app-or-id> | --rect x,y,w,h] [--direct]
    Error: \(error)
    """)
}

Permissions.request()
let status = Permissions.status()
guard status.allGranted else {
    var msg = "Missing permissions. Enable in System Settings > Privacy & Security:\n"
    if !status.screenRecording { msg += "  • Screen Recording\n" }
    if !status.accessibility { msg += "  • Accessibility\n" }
    fail(msg)
}

let createdISO = ISO8601DateFormatter().string(from: Date())

let sema = DispatchSemaphore(value: 0)
Task {
    // The top-level #available guard above does not propagate into this async
    // closure, so re-assert it here for the @available(macOS 12.3) calls below.
    guard #available(macOS 12.3, *) else { exit(1) }
    do {
        let target = try await TargetResolver.resolve(
            displayIndex: options.displayIndex,
            windowQuery: options.windowQuery,
            region: options.region)
        let result = try await Recorder.record(
            target: target, seconds: options.seconds,
            outBundle: URL(fileURLWithPath: options.out),
            appVersion: ShortsCastCapture.version, createdISO: createdISO)
        print("Wrote \(result.bundleURL.path)")
        print("Events: \(result.eventLog.events.count), duration: \(String(format: "%.2f", result.eventLog.duration))s")
        if options.runDirect {
            let dr = Director(settings: AutoDirectorSettings())
                .direct(log: result.eventLog, overrides: [])
            print("Director: \(dr.segments.count) segments, \(dr.cameraPath.keyframes.count) keyframes")
        }
        sema.signal()
    } catch {
        FileHandle.standardError.write(Data("Recording failed: \(error)\n".utf8))
        exit(2)
    }
}
sema.wait()
```

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build`
Expected: succeeds; `shortscast-rec` executable is produced.

- [ ] **Step 7: Commit**

```bash
git add Sources/ShortsCastCapture/CLIOptions.swift Sources/shortscast-rec/main.swift Tests/ShortsCastCaptureTests/CLIOptionsTests.swift
git commit -m "feat: add CLI option parsing and shortscast-rec main"
```

---

### Task 12: Manual end-to-end verification

**Files:** none (verification + a short results note).

**Interfaces:** Consumes the whole `shortscast-rec` binary.

This task is run by a human (or an agent that can grant permissions) on this Mac. It verifies the OS-bound layers that unit tests cannot.

- [ ] **Step 1: Build the release binary**

Run: `swift build -c release`
Expected: succeeds; binary at `.build/release/shortscast-rec`.

- [ ] **Step 2: First run — expect a permissions prompt**

Run: `.build/release/shortscast-rec --seconds 5 --out /tmp/test.shortscast --direct`
Expected (first time): it requests Screen Recording + Accessibility and exits non-zero listing what to enable. Grant both in System Settings, then re-run.

- [ ] **Step 3: Full-display capture run**

During the 5 seconds, click around and type. After it finishes, expected stdout:
- `Wrote /tmp/test.shortscast`
- a non-zero `Events:` count
- `Director: N segments, M keyframes` with N ≥ 1 (because you clicked).

- [ ] **Step 4: Inspect the bundle**

Run: `ls /tmp/test.shortscast` (expect `raw.mov`, `events.json`, `meta.json`), then open `raw.mov` (`open /tmp/test.shortscast/raw.mov`) and confirm it plays and shows what was on screen. Spot-check `events.json`: click points should be within the display's pixel bounds and t values within `[0, duration]`.

- [ ] **Step 5: Region capture run**

Run: `.build/release/shortscast-rec --seconds 4 --out /tmp/region.shortscast --rect 0,0,640,480 --direct`
Expected: `raw.mov` is 640×480-region content (×backing scale), plays correctly; clicks inside the region appear in `events.json`, clicks outside are absent.

- [ ] **Step 6: Record results**

Append a short note to the report file (pass/fail per step, any anomalies). No commit needed unless a code fix was required — if a fix was needed, commit it and re-run the affected step.

---

## Self-Review

**Spec coverage:**
- Capture targets display/window/region → Task 10 (`TargetResolver`) + Task 8 (region crop) + Task 11 (CLI flags); manual verify Task 12.
- Coordinate model (translate+scale, top-left, out-of-bounds drop) → Task 2 (`CaptureGeometry`), Task 3 (`EventMapper`).
- Event recorder (clicks/keys/scroll/cursor, no keycodes) → Task 9 (`EventTap`), Task 3 (mapping).
- Shared clock + rebase to first frame + 60 Hz cursor throttle → Task 4 (`machNowSeconds`/converter), Task 5 (`EventLogBuilder`), Task 8 (`firstFramePTSSeconds`).
- H.264/60fps/.mov, region via CoreImage crop → Task 8.
- Project bundle (raw.mov + events.json + meta.json) → Task 6.
- Permissions check/prompt + clear exit → Task 7, Task 11.
- macOS 12.3 guard → Task 8/10 (`@available`), Task 11 (runtime guard).
- `--direct` end-to-end smoke through `Director` → Task 11, Task 12.
- Pure code never reads a wall clock (created date passed in) → Task 6 (`BundleMeta.created`), Task 11 (computes ISO date).

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step has complete Swift. OS-bound tasks use `swift build` + Task 12 manual run instead of unit tests by design (documented in the spec's testing section).

**Type consistency:** `CaptureGeometry(captureRect:scale:)`, `mapToPixels` → used identically in Tasks 3, 5, 10. `RawInputEvent`/`RawKind` fields consistent Tasks 3, 5, 9. `EventLogBuilder.build(firstFrameT:endT:)` matches `ScreenCaptureSession.stop()`'s `(firstFrameT, endT)` return and `Recorder` call site. `ResolvedTarget` fields produced in Task 10 match `Recorder`'s usage. `CLIOptions` fields produced in Task 11 match `TargetResolver.resolve` / `Recorder.record` parameters. `BundleMeta` fields consistent Tasks 6, 10. Reused core types (`EventLog`, `RecordingEvent`, `MouseButton`, `Director`, `AutoDirectorSettings`) match their Plan 1 signatures.

## Notes for later plans

- Plan 3 (Compositor & Export) reads a `.shortscast` bundle via `ProjectBundle.read`, runs `Director`, and renders `raw.mov` through the crop rects.
- Plan 4 (Editor UI) reuses `ShortsCastCapture` (Recorder/TargetResolver) and adds interactive display/window/region pickers in place of CLI flags; window capture can then track live window-move (a limitation documented here).
