# ShortsCast Core Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `ShortsCastCore`, a pure-Swift package containing the deterministic "brain" of ShortsCast — event models, event clustering, the Auto-Director (auto-zoom keyframe generation), virtual-camera/format-fitting math, spring-based smoothing, and the cursor track — fully covered by unit tests.

**Architecture:** A standalone Swift Package with no AppKit/ScreenCaptureKit/AVFoundation dependency. Input is an `EventLog` (raw recording metadata) plus settings; output is an editable `CameraPath` and `CursorTrack`. Everything is a pure function of its inputs so the same recording always produces the same result, which makes the whole module unit-testable without capture or UI. Later plans (capture, compositor, editor) consume this library.

**Tech Stack:** Swift 5.7 (Xcode 14.2 toolchain), Swift Package Manager, XCTest, Foundation + CoreGraphics (for `CGPoint`/`CGRect`/`CGSize`).

## Global Constraints

- Platform floor: `.macOS(.v13)` (chosen now so later capture plans can add ScreenCaptureKit to the same package graph).
- Swift tools version: `5.7` (matches the installed toolchain, Swift 5.7.2 / Xcode 14.2).
- No dependencies on AppKit, ScreenCaptureKit, AVFoundation, or Metal in this package — pure logic only.
- All time values are `Seconds` (`typealias Seconds = Double`), relative to recording start.
- All screen coordinates are in **pixels, origin top-left**, matching ScreenCaptureKit's frame space.
- `OutputFormat.aspectRatio` is defined as `width / height`.
- Every public type used across tasks is `public`; types crossing the JSON boundary (`RecordingEvent`, `EventLog`, `OutputFormat`) are `Codable`.
- TDD throughout: failing test first, minimal implementation, passing test, commit.

---

### Task 1: Swift Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/ShortsCastCore/ShortsCastCore.swift`
- Test: `Tests/ShortsCastCoreTests/ScaffoldTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable package named `ShortsCastCore` with a test target `ShortsCastCoreTests`; a marker constant `ShortsCastCore.version: String`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/ScaffoldTests.swift
import XCTest
@testable import ShortsCastCore

final class ScaffoldTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(ShortsCastCore.version.isEmpty)
    }
}
```

- [ ] **Step 2: Create the package manifest**

```swift
// Package.swift
// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ShortsCastCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShortsCastCore", targets: ["ShortsCastCore"])
    ],
    targets: [
        .target(name: "ShortsCastCore"),
        .testTarget(name: "ShortsCastCoreTests", dependencies: ["ShortsCastCore"])
    ]
)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test`
Expected: FAIL — compile error, `ShortsCastCore.version` / source file does not exist.

- [ ] **Step 4: Write minimal implementation**

```swift
// Sources/ShortsCastCore/ShortsCastCore.swift
import Foundation

public enum ShortsCastCore {
    public static let version = "0.1.0"
}

/// Seconds since recording start.
public typealias Seconds = Double
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test`
Expected: PASS — `ScaffoldTests.test_version_isNonEmpty` passes.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: scaffold ShortsCastCore swift package"
```

---

### Task 2: Recording event model + EventLog

**Files:**
- Create: `Sources/ShortsCastCore/Models/RecordingEvent.swift`
- Create: `Sources/ShortsCastCore/Models/EventLog.swift`
- Test: `Tests/ShortsCastCoreTests/EventLogTests.swift`

**Interfaces:**
- Consumes: `Seconds` (Task 1).
- Produces:
  - `enum MouseButton: String, Codable { case left, right, other }`
  - `enum EventType: String, Codable { case click, key, scroll, cursor }`
  - `struct RecordingEvent: Codable, Equatable { var t: Seconds; var type: EventType; var point: CGPoint?; var button: MouseButton?; var deltaY: Double? }`
  - `struct EventLog: Codable, Equatable { var duration: Seconds; var screenSize: CGSize; var events: [RecordingEvent] }`
  - Convenience initializers: `RecordingEvent.click(t:point:button:)`, `.key(t:)`, `.scroll(t:point:deltaY:)`, `.cursor(t:point:)`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/EventLogTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class EventLogTests: XCTestCase {
    func test_eventLog_jsonRoundTrip_preservesEvents() throws {
        let log = EventLog(
            duration: 5,
            screenSize: CGSize(width: 1920, height: 1080),
            events: [
                .click(t: 1.0, point: CGPoint(x: 100, y: 200), button: .left),
                .key(t: 1.2),
                .scroll(t: 2.0, point: CGPoint(x: 50, y: 60), deltaY: -3),
                .cursor(t: 2.1, point: CGPoint(x: 51, y: 61))
            ]
        )
        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(EventLog.self, from: data)
        XCTAssertEqual(decoded, log)
        XCTAssertEqual(decoded.events[1].type, .key)
        XCTAssertNil(decoded.events[1].point)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EventLogTests`
Expected: FAIL — `EventLog` / `RecordingEvent` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/Models/RecordingEvent.swift
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
```

```swift
// Sources/ShortsCastCore/Models/EventLog.swift
import Foundation
import CoreGraphics

/// The raw, lossless metadata captured alongside the screen recording.
public struct EventLog: Codable, Equatable {
    public var duration: Seconds
    public var screenSize: CGSize
    public var events: [RecordingEvent]

    public init(duration: Seconds, screenSize: CGSize, events: [RecordingEvent]) {
        self.duration = duration
        self.screenSize = screenSize
        self.events = events
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EventLogTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/Models Tests/ShortsCastCoreTests/EventLogTests.swift
git commit -m "feat: add RecordingEvent and EventLog models"
```

---

### Task 3: Math helpers (lerp, smootherstep, clamp)

**Files:**
- Create: `Sources/ShortsCastCore/Math.swift`
- Test: `Tests/ShortsCastCoreTests/MathTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double`
  - `func smootherstep(_ x: Double) -> Double` — Perlin smootherstep `6x^5-15x^4+10x^3`, clamps input to `[0,1]`.
  - `func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/MathTests.swift
import XCTest
@testable import ShortsCastCore

final class MathTests: XCTestCase {
    func test_lerp_midpoint() {
        XCTAssertEqual(lerp(0, 10, 0.5), 5, accuracy: 1e-9)
    }
    func test_smootherstep_endpointsAndMid() {
        XCTAssertEqual(smootherstep(0), 0, accuracy: 1e-9)
        XCTAssertEqual(smootherstep(1), 1, accuracy: 1e-9)
        XCTAssertEqual(smootherstep(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(smootherstep(-2), 0, accuracy: 1e-9) // clamps
    }
    func test_clamp() {
        XCTAssertEqual(clampD(5, 0, 3), 3, accuracy: 1e-9)
        XCTAssertEqual(clampD(-1, 0, 3), 0, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MathTests`
Expected: FAIL — `lerp`/`smootherstep`/`clampD` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/Math.swift
import Foundation

public func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(max(v, lo), hi)
}

public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

/// Perlin smootherstep: 6x^5 - 15x^4 + 10x^3, with x clamped to [0,1].
public func smootherstep(_ x: Double) -> Double {
    let t = clampD(x, 0, 1)
    return t * t * t * (t * (t * 6 - 15) + 10)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MathTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/Math.swift Tests/ShortsCastCoreTests/MathTests.swift
git commit -m "feat: add math helpers (lerp, smootherstep, clamp)"
```

---

### Task 4: OutputFormat model + presets

**Files:**
- Create: `Sources/ShortsCastCore/Models/OutputFormat.swift`
- Test: `Tests/ShortsCastCoreTests/OutputFormatTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct OutputFormat: Equatable, Codable { let name: String; let aspect: CGSize; let exportSize: CGSize; var aspectRatio: CGFloat { get } }`
  - Presets: `.vertical9x16` (1080×1920), `.square1x1` (1080×1080), `.portrait4x5` (1080×1350), `.landscape16x9` (1920×1080)
  - `static var all: [OutputFormat]`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/OutputFormatTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class OutputFormatTests: XCTestCase {
    func test_vertical_aspectRatio() {
        XCTAssertEqual(OutputFormat.vertical9x16.aspectRatio, 9.0/16.0, accuracy: 1e-6)
        XCTAssertEqual(OutputFormat.vertical9x16.exportSize, CGSize(width: 1080, height: 1920))
    }
    func test_all_containsFourPresets() {
        XCTAssertEqual(OutputFormat.all.count, 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OutputFormatTests`
Expected: FAIL — `OutputFormat` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/Models/OutputFormat.swift
import Foundation
import CoreGraphics

/// A social-media output target. `aspect` is the ratio shape; `exportSize` the pixel size.
public struct OutputFormat: Equatable, Codable {
    public let name: String
    public let aspect: CGSize
    public let exportSize: CGSize

    public init(name: String, aspect: CGSize, exportSize: CGSize) {
        self.name = name; self.aspect = aspect; self.exportSize = exportSize
    }

    /// width / height
    public var aspectRatio: CGFloat { aspect.width / aspect.height }

    public static let vertical9x16 = OutputFormat(
        name: "9:16", aspect: CGSize(width: 9, height: 16),
        exportSize: CGSize(width: 1080, height: 1920))
    public static let square1x1 = OutputFormat(
        name: "1:1", aspect: CGSize(width: 1, height: 1),
        exportSize: CGSize(width: 1080, height: 1080))
    public static let portrait4x5 = OutputFormat(
        name: "4:5", aspect: CGSize(width: 4, height: 5),
        exportSize: CGSize(width: 1080, height: 1350))
    public static let landscape16x9 = OutputFormat(
        name: "16:9", aspect: CGSize(width: 16, height: 9),
        exportSize: CGSize(width: 1920, height: 1080))

    public static let all: [OutputFormat] =
        [.vertical9x16, .square1x1, .portrait4x5, .landscape16x9]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter OutputFormatTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/Models/OutputFormat.swift Tests/ShortsCastCoreTests/OutputFormatTests.swift
git commit -m "feat: add OutputFormat model with social presets"
```

---

### Task 5: Camera state, keyframe, and path sampling

**Files:**
- Create: `Sources/ShortsCastCore/Models/CameraPath.swift`
- Test: `Tests/ShortsCastCoreTests/CameraPathTests.swift`

**Interfaces:**
- Consumes: `lerp`, `smootherstep` (Task 3).
- Produces:
  - `struct CameraState: Equatable { var center: CGPoint; var scale: CGFloat }`
  - `struct CameraKeyframe: Equatable { var t: Seconds; var center: CGPoint; var scale: CGFloat; var state: CameraState { get } }`
  - `struct CameraPath: Equatable { var keyframes: [CameraKeyframe]; func sample(at t: Seconds) -> CameraState }`
  - Sampling clamps before the first / after the last keyframe and uses smootherstep easing between adjacent keyframes.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/CameraPathTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class CameraPathTests: XCTestCase {
    private func path() -> CameraPath {
        CameraPath(keyframes: [
            CameraKeyframe(t: 0, center: CGPoint(x: 0, y: 0), scale: 1),
            CameraKeyframe(t: 2, center: CGPoint(x: 100, y: 0), scale: 2)
        ])
    }
    func test_sample_clampsBeforeStartAndAfterEnd() {
        XCTAssertEqual(path().sample(at: -1).scale, 1, accuracy: 1e-6)
        XCTAssertEqual(path().sample(at: 99).scale, 2, accuracy: 1e-6)
    }
    func test_sample_midpoint_usesSmootherstepEasing() {
        // smootherstep(0.5) == 0.5, so midpoint is exactly halfway
        let s = path().sample(at: 1)
        XCTAssertEqual(s.center.x, 50, accuracy: 1e-6)
        XCTAssertEqual(s.scale, 1.5, accuracy: 1e-6)
    }
    func test_sample_quarter_isEasedNotLinear() {
        // at t=0.5 (u=0.25) easing < linear, so center.x < 25
        let s = path().sample(at: 0.5)
        XCTAssertLessThan(s.center.x, 25)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CameraPathTests`
Expected: FAIL — `CameraPath` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/Models/CameraPath.swift
import Foundation
import CoreGraphics

/// The camera at an instant: where it looks (`center`, screen px) and how tight (`scale`, 1=resting).
public struct CameraState: Equatable {
    public var center: CGPoint
    public var scale: CGFloat
    public init(center: CGPoint, scale: CGFloat) { self.center = center; self.scale = scale }
}

public struct CameraKeyframe: Equatable {
    public var t: Seconds
    public var center: CGPoint
    public var scale: CGFloat
    public init(t: Seconds, center: CGPoint, scale: CGFloat) {
        self.t = t; self.center = center; self.scale = scale
    }
    public var state: CameraState { CameraState(center: center, scale: scale) }
}

/// An editable, eased path of the virtual camera over time.
public struct CameraPath: Equatable {
    public var keyframes: [CameraKeyframe]
    public init(keyframes: [CameraKeyframe]) { self.keyframes = keyframes }

    public func sample(at t: Seconds) -> CameraState {
        guard let first = keyframes.first else {
            return CameraState(center: .zero, scale: 1)
        }
        if t <= first.t { return first.state }
        guard let last = keyframes.last, t < last.t else {
            return keyframes.last!.state
        }
        var lo = first
        for kf in keyframes {
            if kf.t <= t { lo = kf; continue }
            let hi = kf
            let span = hi.t - lo.t
            let u = span > 0 ? (t - lo.t) / span : 0
            let e = smootherstep(u)
            return CameraState(
                center: CGPoint(x: lerp(Double(lo.center.x), Double(hi.center.x), e),
                                y: lerp(Double(lo.center.y), Double(hi.center.y), e)),
                scale: CGFloat(lerp(Double(lo.scale), Double(hi.scale), e)))
        }
        return last.state
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CameraPathTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/Models/CameraPath.swift Tests/ShortsCastCoreTests/CameraPathTests.swift
git commit -m "feat: add CameraState/Keyframe/Path with eased sampling"
```

---

### Task 6: Auto-Director settings + focus segment model

**Files:**
- Create: `Sources/ShortsCastCore/AutoDirector/AutoDirectorSettings.swift`
- Create: `Sources/ShortsCastCore/AutoDirector/FocusSegment.swift`
- Test: `Tests/ShortsCastCoreTests/AutoDirectorSettingsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct AutoDirectorSettings` with defaults:
    `defaultZoom: CGFloat = 2.5`, `maxZoom: CGFloat = 4.0`, `restingZoom: CGFloat = 1.0`,
    `clusterTimeGap: Seconds = 1.5`, `clusterRadius: CGFloat = 300`,
    `inactivityTimeout: Seconds = 1.5`, `zoomInDuration: Seconds = 0.4`, `zoomOutDuration: Seconds = 0.6`,
    `clickWeight: Double = 1.0`, `keyWeight: Double = 0.6`, `scrollWeight: Double = 0.5`, `dwellWeight: Double = 0.4`,
    `denseEventCount: Int = 5`, `denseZoomBonus: CGFloat = 0.5`.
  - `struct FocusSegment: Equatable { var start: Seconds; var end: Seconds; var center: CGPoint; var zoom: CGFloat }` (all stored properties `var` so overrides can mutate them).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/AutoDirectorSettingsTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class AutoDirectorSettingsTests: XCTestCase {
    func test_defaults() {
        let s = AutoDirectorSettings()
        XCTAssertEqual(s.defaultZoom, 2.5, accuracy: 1e-6)
        XCTAssertEqual(s.maxZoom, 4.0, accuracy: 1e-6)
        XCTAssertEqual(s.clusterTimeGap, 1.5, accuracy: 1e-6)
    }
    func test_focusSegment_isMutable() {
        var seg = FocusSegment(start: 0, end: 1, center: .zero, zoom: 2)
        seg.zoom = 3
        XCTAssertEqual(seg.zoom, 3, accuracy: 1e-6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AutoDirectorSettingsTests`
Expected: FAIL — `AutoDirectorSettings` / `FocusSegment` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/AutoDirector/AutoDirectorSettings.swift
import Foundation
import CoreGraphics

/// Tunables that drive auto-zoom generation. User-facing global zoom controls live here.
public struct AutoDirectorSettings {
    public var defaultZoom: CGFloat = 2.5
    public var maxZoom: CGFloat = 4.0
    public var restingZoom: CGFloat = 1.0
    public var clusterTimeGap: Seconds = 1.5
    public var clusterRadius: CGFloat = 300
    public var inactivityTimeout: Seconds = 1.5
    public var zoomInDuration: Seconds = 0.4
    public var zoomOutDuration: Seconds = 0.6
    public var clickWeight: Double = 1.0
    public var keyWeight: Double = 0.6
    public var scrollWeight: Double = 0.5
    public var dwellWeight: Double = 0.4
    public var denseEventCount: Int = 5
    public var denseZoomBonus: CGFloat = 0.5

    public init() {}
}
```

```swift
// Sources/ShortsCastCore/AutoDirector/FocusSegment.swift
import Foundation
import CoreGraphics

/// A clustered window of activity the camera should focus on.
public struct FocusSegment: Equatable {
    public var start: Seconds
    public var end: Seconds
    public var center: CGPoint
    public var zoom: CGFloat
    public init(start: Seconds, end: Seconds, center: CGPoint, zoom: CGFloat) {
        self.start = start; self.end = end; self.center = center; self.zoom = zoom
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AutoDirectorSettingsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/AutoDirector Tests/ShortsCastCoreTests/AutoDirectorSettingsTests.swift
git commit -m "feat: add AutoDirectorSettings and FocusSegment"
```

---

### Task 7: Event clusterer (events → focus segments)

**Files:**
- Create: `Sources/ShortsCastCore/AutoDirector/EventClusterer.swift`
- Test: `Tests/ShortsCastCoreTests/EventClustererTests.swift`

**Interfaces:**
- Consumes: `EventLog`, `RecordingEvent`, `EventType` (Task 2); `AutoDirectorSettings`, `FocusSegment` (Task 6).
- Produces:
  - `struct EventClusterer { init(settings: AutoDirectorSettings); func segments(from log: EventLog) -> [FocusSegment] }`
  - Rules: `cursor` events are ignored for clustering. Triggering events within `clusterTimeGap` of the previous event **and** within `clusterRadius` of the running centroid join the current cluster; otherwise a new cluster starts. Centroid is weighted by per-type weight, over events that have a `point`. A cluster with no positional events is dropped. Zoom = `defaultZoom`, plus `denseZoomBonus` if event count ≥ `denseEventCount`, capped at `maxZoom`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/EventClustererTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class EventClustererTests: XCTestCase {
    private func clusterer() -> EventClusterer { EventClusterer(settings: AutoDirectorSettings()) }

    func test_nearbyClicks_mergeIntoOneSegment() {
        let log = EventLog(duration: 10, screenSize: CGSize(width: 1920, height: 1080), events: [
            .click(t: 1.0, point: CGPoint(x: 100, y: 100), button: .left),
            .click(t: 1.3, point: CGPoint(x: 110, y: 105), button: .left),
            .click(t: 1.6, point: CGPoint(x: 90, y: 95), button: .left)
        ])
        let segs = clusterer().segments(from: log)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].start, 1.0, accuracy: 1e-6)
        XCTAssertEqual(segs[0].end, 1.6, accuracy: 1e-6)
        XCTAssertEqual(segs[0].center.x, 100, accuracy: 5) // ~centroid
    }

    func test_distantInTime_splitsIntoTwoSegments() {
        let log = EventLog(duration: 20, screenSize: CGSize(width: 1920, height: 1080), events: [
            .click(t: 1.0, point: CGPoint(x: 100, y: 100), button: .left),
            .click(t: 10.0, point: CGPoint(x: 100, y: 100), button: .left)
        ])
        XCTAssertEqual(clusterer().segments(from: log).count, 2)
    }

    func test_distantInSpace_splitsIntoTwoSegments() {
        let log = EventLog(duration: 10, screenSize: CGSize(width: 1920, height: 1080), events: [
            .click(t: 1.0, point: CGPoint(x: 100, y: 100), button: .left),
            .click(t: 1.2, point: CGPoint(x: 1800, y: 1000), button: .left)
        ])
        XCTAssertEqual(clusterer().segments(from: log).count, 2)
    }

    func test_cursorSamplesIgnored() {
        let log = EventLog(duration: 10, screenSize: CGSize(width: 1920, height: 1080), events: [
            .cursor(t: 0.5, point: CGPoint(x: 10, y: 10)),
            .cursor(t: 0.8, point: CGPoint(x: 20, y: 20))
        ])
        XCTAssertTrue(clusterer().segments(from: log).isEmpty)
    }

    func test_denseCluster_getsZoomBonus() {
        let s = AutoDirectorSettings()
        var events: [RecordingEvent] = []
        for i in 0..<6 { events.append(.click(t: 1.0 + Double(i) * 0.2,
                                               point: CGPoint(x: 100, y: 100), button: .left)) }
        let log = EventLog(duration: 10, screenSize: CGSize(width: 1920, height: 1080), events: events)
        let segs = EventClusterer(settings: s).segments(from: log)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].zoom, min(s.defaultZoom + s.denseZoomBonus, s.maxZoom), accuracy: 1e-6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EventClustererTests`
Expected: FAIL — `EventClusterer` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/AutoDirector/EventClusterer.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EventClustererTests`
Expected: PASS — all five cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/AutoDirector/EventClusterer.swift Tests/ShortsCastCoreTests/EventClustererTests.swift
git commit -m "feat: cluster events into focus segments"
```

---

### Task 8: Auto-Director (focus segments → camera path)

**Files:**
- Create: `Sources/ShortsCastCore/AutoDirector/AutoDirector.swift`
- Test: `Tests/ShortsCastCoreTests/AutoDirectorTests.swift`

**Interfaces:**
- Consumes: `FocusSegment`, `AutoDirectorSettings` (Task 6); `CameraState`, `CameraKeyframe`, `CameraPath` (Task 5).
- Produces:
  - `struct AutoDirector { init(settings: AutoDirectorSettings); func cameraPath(segments: [FocusSegment], duration: Seconds, screenSize: CGSize) -> CameraPath }`
  - Behavior: starts at resting (center = screen center, scale = `restingZoom`) at t=0. Per segment, holds the current state until `segment.start`, eases to the segment target over `zoomInDuration`, holds through `segment.end`. If the gap to the next segment exceeds `inactivityTimeout` (or it's the last segment), eases back to resting after the timeout over `zoomOutDuration`; otherwise stays zoomed and the next segment pans from the current state. Keyframe times are kept strictly increasing. A final keyframe extends the path to `duration`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/AutoDirectorTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class AutoDirectorTests: XCTestCase {
    private let screen = CGSize(width: 1920, height: 1080)

    func test_singleSegment_zoomsInThenBackToResting() {
        let s = AutoDirectorSettings()
        let seg = FocusSegment(start: 2.0, end: 2.5, center: CGPoint(x: 400, y: 300), zoom: 2.5)
        let path = AutoDirector(settings: s).cameraPath(segments: [seg], duration: 10, screenSize: screen)

        // Resting at the very start.
        XCTAssertEqual(path.sample(at: 0).scale, s.restingZoom, accuracy: 1e-6)
        XCTAssertEqual(path.sample(at: 0).center.x, screen.width / 2, accuracy: 1e-6)

        // Fully zoomed while the segment is active.
        let mid = path.sample(at: 2.5)
        XCTAssertEqual(mid.scale, 2.5, accuracy: 1e-6)
        XCTAssertEqual(mid.center.x, 400, accuracy: 1e-6)

        // Back to resting well after inactivity timeout + zoom-out.
        let after = path.sample(at: 2.5 + s.inactivityTimeout + s.zoomOutDuration + 0.5)
        XCTAssertEqual(after.scale, s.restingZoom, accuracy: 1e-6)
    }

    func test_keyframeTimes_areStrictlyIncreasing() {
        let s = AutoDirectorSettings()
        // Two segments close enough to stay zoomed between them.
        let segs = [
            FocusSegment(start: 1.0, end: 1.2, center: CGPoint(x: 200, y: 200), zoom: 2.5),
            FocusSegment(start: 1.4, end: 1.6, center: CGPoint(x: 800, y: 400), zoom: 2.5)
        ]
        let path = AutoDirector(settings: s).cameraPath(segments: segs, duration: 5, screenSize: screen)
        for i in 1..<path.keyframes.count {
            XCTAssertGreaterThan(path.keyframes[i].t, path.keyframes[i-1].t)
        }
    }

    func test_emptySegments_staysRestingForWholeDuration() {
        let path = AutoDirector(settings: AutoDirectorSettings())
            .cameraPath(segments: [], duration: 8, screenSize: screen)
        XCTAssertEqual(path.sample(at: 4).scale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(path.sample(at: 8).center.x, screen.width / 2, accuracy: 1e-6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AutoDirectorTests`
Expected: FAIL — `AutoDirector` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/AutoDirector/AutoDirector.swift
import Foundation
import CoreGraphics

/// Turns focus segments into an editable, eased camera path (the auto-zoom).
public struct AutoDirector {
    public var settings: AutoDirectorSettings
    public init(settings: AutoDirectorSettings) { self.settings = settings }

    public func cameraPath(segments: [FocusSegment],
                           duration: Seconds,
                           screenSize: CGSize) -> CameraPath {
        let rest = CameraState(
            center: CGPoint(x: screenSize.width / 2, y: screenSize.height / 2),
            scale: settings.restingZoom)

        var kfs: [CameraKeyframe] = [CameraKeyframe(t: 0, center: rest.center, scale: rest.scale)]
        var current = rest

        func push(_ t: Seconds, _ s: CameraState) {
            var tt = t
            if let last = kfs.last, tt <= last.t { tt = last.t + 0.001 }
            kfs.append(CameraKeyframe(t: tt, center: s.center, scale: s.scale))
            current = s
        }

        for (i, seg) in segments.enumerated() {
            let target = CameraState(center: seg.center, scale: seg.zoom)
            push(seg.start, current)                                   // hold until move begins
            push(seg.start + settings.zoomInDuration, target)         // ease in
            push(max(seg.end, seg.start + settings.zoomInDuration), target) // hold while active

            let nextStart = i + 1 < segments.count ? segments[i + 1].start : Double.infinity
            let gap = nextStart - seg.end
            if gap > settings.inactivityTimeout {
                push(seg.end + settings.inactivityTimeout, target)    // hold, then
                push(seg.end + settings.inactivityTimeout + settings.zoomOutDuration, rest) // zoom out
            }
            // else: stay zoomed; the next segment pans/zooms from `current`.
        }

        if let last = kfs.last, last.t < duration {
            push(duration, current)
        }
        return CameraPath(keyframes: kfs)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AutoDirectorTests`
Expected: PASS — all three cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/AutoDirector/AutoDirector.swift Tests/ShortsCastCoreTests/AutoDirectorTests.swift
git commit -m "feat: generate eased camera path from focus segments"
```

---

### Task 9: Per-segment overrides

**Files:**
- Create: `Sources/ShortsCastCore/AutoDirector/SegmentOverride.swift`
- Test: `Tests/ShortsCastCoreTests/SegmentOverrideTests.swift`

**Interfaces:**
- Consumes: `FocusSegment` (Task 6).
- Produces:
  - `struct SegmentOverride: Equatable { var index: Int; var zoom: CGFloat?; var center: CGPoint? }`
  - `func applyOverrides(_ segments: [FocusSegment], _ overrides: [SegmentOverride]) -> [FocusSegment]` — applies each override to the segment at its index (ignoring out-of-range indices), overwriting `zoom` and/or `center` when present. This is how the editor's manual zoom-× edits persist across regeneration.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/SegmentOverrideTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class SegmentOverrideTests: XCTestCase {
    private func segs() -> [FocusSegment] {
        [FocusSegment(start: 0, end: 1, center: CGPoint(x: 10, y: 10), zoom: 2.5),
         FocusSegment(start: 2, end: 3, center: CGPoint(x: 20, y: 20), zoom: 2.5)]
    }
    func test_zoomOverride_appliesToCorrectSegment() {
        let out = applyOverrides(segs(), [SegmentOverride(index: 1, zoom: 3.2, center: nil)])
        XCTAssertEqual(out[0].zoom, 2.5, accuracy: 1e-6)
        XCTAssertEqual(out[1].zoom, 3.2, accuracy: 1e-6)
    }
    func test_centerOverride_applies() {
        let out = applyOverrides(segs(), [SegmentOverride(index: 0, zoom: nil, center: CGPoint(x: 99, y: 88))])
        XCTAssertEqual(out[0].center, CGPoint(x: 99, y: 88))
    }
    func test_outOfRangeIndex_ignored() {
        let out = applyOverrides(segs(), [SegmentOverride(index: 9, zoom: 3, center: nil)])
        XCTAssertEqual(out, segs())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SegmentOverrideTests`
Expected: FAIL — `SegmentOverride` / `applyOverrides` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/AutoDirector/SegmentOverride.swift
import Foundation
import CoreGraphics

/// A manual edit to a generated focus segment (e.g. the user sets this zoom to 3×).
public struct SegmentOverride: Equatable {
    public var index: Int
    public var zoom: CGFloat?
    public var center: CGPoint?
    public init(index: Int, zoom: CGFloat? = nil, center: CGPoint? = nil) {
        self.index = index; self.zoom = zoom; self.center = center
    }
}

/// Applies overrides by segment index; out-of-range indices are ignored.
public func applyOverrides(_ segments: [FocusSegment],
                           _ overrides: [SegmentOverride]) -> [FocusSegment] {
    var out = segments
    for o in overrides where o.index >= 0 && o.index < out.count {
        if let z = o.zoom { out[o.index].zoom = z }
        if let c = o.center { out[o.index].center = c }
    }
    return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SegmentOverrideTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/AutoDirector/SegmentOverride.swift Tests/ShortsCastCoreTests/SegmentOverrideTests.swift
git commit -m "feat: apply per-segment zoom/center overrides"
```

---

### Task 10: Virtual camera (format fitting → crop rect)

**Files:**
- Create: `Sources/ShortsCastCore/Camera/VirtualCamera.swift`
- Test: `Tests/ShortsCastCoreTests/VirtualCameraTests.swift`

**Interfaces:**
- Consumes: `CameraState` (Task 5), `OutputFormat` (Task 4).
- Produces:
  - `enum VirtualCamera`
    - `static func baseCropSize(screen: CGSize, format: OutputFormat) -> CGSize` — the resting (scale 1) crop: the largest rect of the format's aspect ratio that fits inside the screen.
    - `static func cropRect(state: CameraState, format: OutputFormat, screen: CGSize) -> CGRect` — base crop divided by `state.scale`, clamped to ≤ screen, centered on `state.center`, then translated so it stays fully within `[0,screen]`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/VirtualCameraTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class VirtualCameraTests: XCTestCase {
    private let screen = CGSize(width: 1920, height: 1080)

    func test_baseCrop_vertical_isLimitedByHeight() {
        let base = VirtualCamera.baseCropSize(screen: screen, format: .vertical9x16)
        XCTAssertEqual(base.height, 1080, accuracy: 1e-6)
        XCTAssertEqual(base.width, 1080 * 9.0 / 16.0, accuracy: 1e-6) // 607.5
    }

    func test_baseCrop_landscapeMatchingScreen_isFullScreen() {
        let base = VirtualCamera.baseCropSize(screen: screen, format: .landscape16x9)
        XCTAssertEqual(base.width, 1920, accuracy: 1e-6)
        XCTAssertEqual(base.height, 1080, accuracy: 1e-6)
    }

    func test_restingVerticalCrop_isCentered() {
        let rect = VirtualCamera.cropRect(
            state: CameraState(center: CGPoint(x: 960, y: 540), scale: 1),
            format: .vertical9x16, screen: screen)
        XCTAssertEqual(rect.width, 607.5, accuracy: 1e-3)
        XCTAssertEqual(rect.height, 1080, accuracy: 1e-6)
        XCTAssertEqual(rect.midX, 960, accuracy: 1e-3)
    }

    func test_zoomedCrop_shrinksAndCentersOnPoint() {
        let rect = VirtualCamera.cropRect(
            state: CameraState(center: CGPoint(x: 500, y: 400), scale: 2),
            format: .vertical9x16, screen: screen)
        XCTAssertEqual(rect.width, 607.5 / 2, accuracy: 1e-3)
        XCTAssertEqual(rect.height, 540, accuracy: 1e-6)
        XCTAssertEqual(rect.midX, 500, accuracy: 1e-3)
        XCTAssertEqual(rect.midY, 400, accuracy: 1e-3)
    }

    func test_cropNearEdge_isClampedInsideScreen() {
        let rect = VirtualCamera.cropRect(
            state: CameraState(center: CGPoint(x: 0, y: 0), scale: 2),
            format: .vertical9x16, screen: screen)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, screen.width + 1e-6)
        XCTAssertLessThanOrEqual(rect.maxY, screen.height + 1e-6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VirtualCameraTests`
Expected: FAIL — `VirtualCamera` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/Camera/VirtualCamera.swift
import Foundation
import CoreGraphics

/// Maps a CameraState + output format to a crop rectangle in screen pixel space.
public enum VirtualCamera {
    /// Largest rect of the format's aspect ratio that fits inside the screen (resting crop).
    public static func baseCropSize(screen: CGSize, format: OutputFormat) -> CGSize {
        let a = format.aspectRatio
        let screenA = screen.width / screen.height
        if a <= screenA {
            // Output is narrower (or equal) than the screen → height-limited.
            return CGSize(width: screen.height * a, height: screen.height)
        } else {
            // Output is wider than the screen → width-limited.
            return CGSize(width: screen.width, height: screen.width / a)
        }
    }

    public static func cropRect(state: CameraState,
                                format: OutputFormat,
                                screen: CGSize) -> CGRect {
        let base = baseCropSize(screen: screen, format: format)
        let z = max(state.scale, 0.0001)
        var w = base.width / z
        var h = base.height / z
        w = min(w, screen.width)
        h = min(h, screen.height)

        var x = state.center.x - w / 2
        var y = state.center.y - h / 2
        x = min(max(x, 0), screen.width - w)
        y = min(max(y, 0), screen.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter VirtualCameraTests`
Expected: PASS — all five cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/Camera/VirtualCamera.swift Tests/ShortsCastCoreTests/VirtualCameraTests.swift
git commit -m "feat: virtual camera crop-rect with format fitting and clamping"
```

---

### Task 11: Spring smoother (critically damped)

**Files:**
- Create: `Sources/ShortsCastCore/Camera/SpringSmoother.swift`
- Test: `Tests/ShortsCastCoreTests/SpringSmootherTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct TimedPoint: Equatable { var t: Seconds; var p: CGPoint }`
  - `struct SpringSmoother { init(frequency: Double = 6); func smooth(_ samples: [TimedPoint]) -> [TimedPoint] }`
  - Behavior: critically-damped spring integrated per-axis with semi-implicit Euler, preserving the first sample's time/position and producing one output per input. Used by the cursor track (Task 12).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/SpringSmootherTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class SpringSmootherTests: XCTestCase {
    func test_convergesTowardConstantTarget() {
        // A step input: jump to (100,0) and hold; smoothed output should approach it.
        var samples: [TimedPoint] = [TimedPoint(t: 0, p: .zero)]
        var t = 0.0
        for _ in 0..<120 { t += 1.0/60.0; samples.append(TimedPoint(t: t, p: CGPoint(x: 100, y: 0))) }
        let out = SpringSmoother(frequency: 6).smooth(samples)
        XCTAssertEqual(out.count, samples.count)
        XCTAssertEqual(out.first!.p, .zero)            // first sample preserved
        XCTAssertEqual(Double(out.last!.p.x), 100, accuracy: 1.0) // converged
    }

    func test_criticallyDamped_doesNotOvershootMuch() {
        var samples: [TimedPoint] = [TimedPoint(t: 0, p: .zero)]
        var t = 0.0
        for _ in 0..<120 { t += 1.0/60.0; samples.append(TimedPoint(t: t, p: CGPoint(x: 100, y: 0))) }
        let out = SpringSmoother(frequency: 6).smooth(samples)
        let maxX = out.map { Double($0.p.x) }.max() ?? 0
        XCTAssertLessThan(maxX, 105) // critical damping → negligible overshoot
    }

    func test_emptyInput_returnsEmpty() {
        XCTAssertTrue(SpringSmoother().smooth([]).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SpringSmootherTests`
Expected: FAIL — `SpringSmoother` / `TimedPoint` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/Camera/SpringSmoother.swift
import Foundation
import CoreGraphics

public struct TimedPoint: Equatable {
    public var t: Seconds
    public var p: CGPoint
    public init(t: Seconds, p: CGPoint) { self.t = t; self.p = p }
}

/// Critically-damped spring filter for smoothing a stream of points (e.g. cursor motion).
public struct SpringSmoother {
    /// Natural angular frequency (higher = snappier tracking).
    public var omega: Double
    public init(frequency: Double = 6) { self.omega = 2 * Double.pi * frequency }

    public func smooth(_ samples: [TimedPoint]) -> [TimedPoint] {
        guard let first = samples.first else { return [] }
        var posX = Double(first.p.x), posY = Double(first.p.y)
        var velX = 0.0, velY = 0.0
        var out: [TimedPoint] = [first]

        for i in 1..<samples.count {
            let dt = max(samples[i].t - samples[i-1].t, 1e-4)
            let tx = Double(samples[i].p.x), ty = Double(samples[i].p.y)
            // Critically damped: x'' = ω²(target - x) - 2ω x'
            let ax = omega * omega * (tx - posX) - 2 * omega * velX
            let ay = omega * omega * (ty - posY) - 2 * omega * velY
            velX += ax * dt; velY += ay * dt          // semi-implicit Euler
            posX += velX * dt; posY += velY * dt
            out.append(TimedPoint(t: samples[i].t, p: CGPoint(x: posX, y: posY)))
        }
        return out
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SpringSmootherTests`
Expected: PASS — all three cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/Camera/SpringSmoother.swift Tests/ShortsCastCoreTests/SpringSmootherTests.swift
git commit -m "feat: add critically-damped spring smoother"
```

---

### Task 12: Cursor track builder (smoothed cursor + click ripples)

**Files:**
- Create: `Sources/ShortsCastCore/Cursor/CursorTrack.swift`
- Test: `Tests/ShortsCastCoreTests/CursorTrackTests.swift`

**Interfaces:**
- Consumes: `EventLog`, `EventType` (Task 2); `SpringSmoother`, `TimedPoint` (Task 11).
- Produces:
  - `struct ClickRipple: Equatable { var t: Seconds; var point: CGPoint }`
  - `struct CursorTrack: Equatable { var samples: [TimedPoint]; var clicks: [ClickRipple] }`
  - `struct CursorTrackBuilder { init(smoother: SpringSmoother); func build(from log: EventLog) -> CursorTrack }` — smooths the `cursor` samples (sorted by time) via the spring, and emits one `ClickRipple` per `click` event that has a point.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/CursorTrackTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class CursorTrackTests: XCTestCase {
    func test_build_smoothsCursorAndCollectsClicks() {
        var events: [RecordingEvent] = []
        var t = 0.0
        events.append(.cursor(t: t, point: .zero))
        for _ in 0..<60 { t += 1.0/60.0; events.append(.cursor(t: t, point: CGPoint(x: 200, y: 0))) }
        events.append(.click(t: 0.5, point: CGPoint(x: 200, y: 0), button: .left))
        let log = EventLog(duration: 2, screenSize: CGSize(width: 1920, height: 1080), events: events)

        let track = CursorTrackBuilder(smoother: SpringSmoother(frequency: 6)).build(from: log)

        XCTAssertEqual(track.samples.count, 61)              // one per cursor sample
        XCTAssertEqual(track.samples.first!.p, .zero)        // first preserved
        XCTAssertGreaterThan(Double(track.samples.last!.p.x), 100) // moved toward target
        XCTAssertEqual(track.clicks.count, 1)
        XCTAssertEqual(track.clicks[0].point, CGPoint(x: 200, y: 0))
    }

    func test_build_ignoresKeyAndScrollForClicks() {
        let log = EventLog(duration: 1, screenSize: CGSize(width: 100, height: 100), events: [
            .key(t: 0.1),
            .scroll(t: 0.2, point: CGPoint(x: 5, y: 5), deltaY: 1)
        ])
        let track = CursorTrackBuilder(smoother: SpringSmoother()).build(from: log)
        XCTAssertTrue(track.clicks.isEmpty)
        XCTAssertTrue(track.samples.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CursorTrackTests`
Expected: FAIL — `CursorTrackBuilder` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/Cursor/CursorTrack.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CursorTrackTests`
Expected: PASS — both cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/Cursor/CursorTrack.swift Tests/ShortsCastCoreTests/CursorTrackTests.swift
git commit -m "feat: build smoothed cursor track with click ripples"
```

---

### Task 13: End-to-end pipeline facade

**Files:**
- Create: `Sources/ShortsCastCore/Director.swift`
- Test: `Tests/ShortsCastCoreTests/DirectorTests.swift`

**Interfaces:**
- Consumes: everything above — `EventLog`, `AutoDirectorSettings`, `EventClusterer`, `AutoDirector`, `SegmentOverride`, `applyOverrides`, `CameraPath`, `CursorTrackBuilder`, `SpringSmoother`, `CursorTrack`, `VirtualCamera`, `OutputFormat`, `CameraState`.
- Produces:
  - `struct DirectorResult: Equatable { var segments: [FocusSegment]; var cameraPath: CameraPath; var cursor: CursorTrack }`
  - `struct Director { init(settings: AutoDirectorSettings); func direct(log: EventLog, overrides: [SegmentOverride]) -> DirectorResult; func cropRect(_ result: DirectorResult, at t: Seconds, format: OutputFormat, screen: CGSize) -> CGRect }`
  - This is the single entry point later plans (compositor/editor) call: log + overrides → segments + camera path + cursor track, and a convenience that samples the path and produces the format-specific crop at a time.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/DirectorTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class DirectorTests: XCTestCase {
    private let screen = CGSize(width: 1920, height: 1080)

    private func sampleLog() -> EventLog {
        EventLog(duration: 6, screenSize: screen, events: [
            .cursor(t: 0.0, point: CGPoint(x: 100, y: 100)),
            .click(t: 2.0, point: CGPoint(x: 400, y: 300), button: .left),
            .click(t: 2.3, point: CGPoint(x: 410, y: 305), button: .left),
            .cursor(t: 2.4, point: CGPoint(x: 410, y: 305))
        ])
    }

    func test_direct_producesSegmentsPathAndCursor() {
        let result = Director(settings: AutoDirectorSettings()).direct(log: sampleLog(), overrides: [])
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertFalse(result.cameraPath.keyframes.isEmpty)
        XCTAssertEqual(result.cursor.clicks.count, 2)
    }

    func test_override_changesGeneratedZoom() {
        let d = Director(settings: AutoDirectorSettings())
        let base = d.direct(log: sampleLog(), overrides: [])
        let overridden = d.direct(log: sampleLog(),
                                  overrides: [SegmentOverride(index: 0, zoom: 3.7, center: nil)])
        XCTAssertEqual(overridden.segments[0].zoom, 3.7, accuracy: 1e-6)
        XCTAssertNotEqual(base.segments[0].zoom, overridden.segments[0].zoom)
    }

    func test_cropRect_atActiveTime_isZoomedRect() {
        let d = Director(settings: AutoDirectorSettings())
        let result = d.direct(log: sampleLog(), overrides: [])
        let rect = d.cropRect(result, at: 2.3, format: .vertical9x16, screen: screen)
        // While zoomed, crop is narrower than the resting vertical crop (607.5).
        XCTAssertLessThan(rect.width, 607.5)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertLessThanOrEqual(rect.maxX, screen.width + 1e-6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DirectorTests`
Expected: FAIL — `Director` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCore/Director.swift
import Foundation
import CoreGraphics

/// The full output of directing one recording.
public struct DirectorResult: Equatable {
    public var segments: [FocusSegment]
    public var cameraPath: CameraPath
    public var cursor: CursorTrack
    public init(segments: [FocusSegment], cameraPath: CameraPath, cursor: CursorTrack) {
        self.segments = segments; self.cameraPath = cameraPath; self.cursor = cursor
    }
}

/// Single entry point: EventLog (+ manual overrides) -> camera path + cursor track.
public struct Director {
    public var settings: AutoDirectorSettings
    public init(settings: AutoDirectorSettings) { self.settings = settings }

    public func direct(log: EventLog, overrides: [SegmentOverride]) -> DirectorResult {
        let clustered = EventClusterer(settings: settings).segments(from: log)
        let segments = applyOverrides(clustered, overrides)
        let path = AutoDirector(settings: settings)
            .cameraPath(segments: segments, duration: log.duration, screenSize: log.screenSize)
        let cursor = CursorTrackBuilder(smoother: SpringSmoother()).build(from: log)
        return DirectorResult(segments: segments, cameraPath: path, cursor: cursor)
    }

    public func cropRect(_ result: DirectorResult,
                         at t: Seconds,
                         format: OutputFormat,
                         screen: CGSize) -> CGRect {
        let state = result.cameraPath.sample(at: t)
        return VirtualCamera.cropRect(state: state, format: format, screen: screen)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DirectorTests`
Expected: PASS — all three cases.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — every test from Tasks 1–13.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortsCastCore/Director.swift Tests/ShortsCastCoreTests/DirectorTests.swift
git commit -m "feat: add Director pipeline facade"
```

---

## Self-Review

**Spec coverage (Core-Engine-relevant sections):**
- Event log model (clicks/keys/scroll/cursor, timestamps, no keystroke content) → Tasks 2, 7 (key events carry no point/content).
- Auto-Director: cluster in time+space, per-segment target, zoom-out gaps, smoothing, trigger weighting → Tasks 6–8.
- User-controllable zoom (global default + max cap; per-segment override) → Task 6 (settings), Task 9 (overrides), Task 13 (wired through `Director`).
- Virtual camera & format fitting (aspect-correct crop, auto-pan via shared camera, resting framing, clamp to bounds) → Tasks 5, 10, 13.
- Output formats 9:16 / 1:1 / 4:5 / 16:9 → Task 4.
- Cursor polish *data* (smoothed positions, click ripples) → Tasks 11, 12. (Drawing/size/auto-hide is a compositor concern — later plan.)
- Testing strategy: pure functions unit-tested with synthetic logs → all tasks.

**Deferred to later plans (correctly out of scope here):** Capture Engine, Event Recorder (live capture), Compositor/Metal rendering, Editor UI, Exporter, Project bundle persistence, permissions. The `Director` facade (Task 13) is the seam those plans build on.

**Placeholder scan:** No TBD/TODO/"handle edge cases" placeholders; every code step contains complete, compilable Swift.

**Type consistency:** `CameraState`/`CameraKeyframe`/`CameraPath` (Task 5) reused unchanged in Tasks 8, 10, 13. `FocusSegment` (Task 6) is `var`-mutable as required by `applyOverrides` (Task 9). `TimedPoint` (Task 11) reused by Task 12. `Director.direct(log:overrides:)` and `cropRect(_:at:format:screen:)` signatures (Task 13) match their callers in tests. `EventType`/`RecordingEvent` field names (`t`, `type`, `point`, `button`, `deltaY`) consistent across Tasks 2, 7, 12.

## Future plans (project roadmap)

- **Plan 2 — Capture & Event Recorder:** ScreenCaptureKit capture to `.mov`; `CGEventTap` for clicks/keys/scroll/cursor → `EventLog`; permissions flow; Project bundle persistence.
- **Plan 3 — Compositor & Export:** Core Image/Metal per-frame render using `Director.cropRect`, styled background, cursor drawing from `CursorTrack`; `AVAssetWriter` export per `OutputFormat`.
- **Plan 4 — Editor UI:** SwiftUI preview canvas, timeline of `FocusSegment`s with zoom-× editing (writing `SegmentOverride`s), inspector, batch export.
