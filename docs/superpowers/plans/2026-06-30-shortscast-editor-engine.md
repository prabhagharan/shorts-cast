# ShortsCast Editor Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `ShortsCastEditor` — a headless, fully unit-tested `EditorModel` view-model that opens a `.shortscast` bundle, runs the `Director`, holds the user's edits (per-segment zoom-× overrides, style, format, global zoom settings), produces a live preview frame via `FrameCompositor`, persists edits to `project.json`, and drives export honoring those overrides.

**Architecture:** All editor logic lives in one `ObservableObject` (`EditorModel`) plus small value types (`ProjectEdits`) and a `FrameSource` abstraction. No SwiftUI. Verified on macOS 12.6 with AVFoundation + Core Image and synthetic test video; only the `@available(macOS 12.3)` `record(...)` orchestration is excluded from automated tests.

**Tech Stack:** Swift 5.7 (Xcode 14.2), SwiftPM, XCTest, Combine (ObservableObject), AVFoundation, Core Image, CoreGraphics.

## Global Constraints

- Swift tools `5.7`; package platform floor `.macOS(.v12)`.
- `ShortsCastEditor` depends on `ShortsCastCore`, `ShortsCastCapture`, `ShortsCastRender`.
- Source frames and `Director.cropRect` are TOP-LEFT pixel space; Core Image is BOTTOM-LEFT (the existing `FrameCompositor` handles the flip). `CIImage(cgImage:)` from `AVAssetImageGenerator` is upright (visual top at high CI y), matching what `FrameCompositor` expects.
- Edits persist non-destructively to `<bundle>/project.json`; `raw.mov`/`events.json` are never modified.
- A malformed/absent `project.json` → start from defaults (`RenderStyle.default`, `.vertical9x16`, `AutoDirectorSettings()`), never a hard failure. Unknown `formatName` → `.vertical9x16`.
- `record(...)` is `@available(macOS 12.3, *)` and not unit-tested (ScreenCaptureKit; verified in Plan 5 on macOS 13+).
- Reused APIs (verbatim): `ProjectBundle.read(_) -> (eventLog: EventLog, meta: BundleMeta, rawVideoURL: URL)`; `ProjectBundle.write(eventLog:meta:rawVideo:to:)`; `Director(settings:).direct(log:overrides:) -> DirectorResult`; `Director.cropRect(_:at:format:screen:) -> CGRect`; `DirectorResult { segments, cameraPath, cursor }`; `FocusSegment { start, end, center, zoom }`; `SegmentOverride(index:zoom:center:)`; `AutoDirectorSettings()` (fields incl. `defaultZoom`, `maxZoom`); `OutputFormat { name, exportSize, static all }`; `RenderStyle.default`; `FrameCompositor(style:format:screenSize:)` + `.composite(source:crop:time:cursor:) -> CIImage` + `.context`; `ExportJob.run(bundleURL:formats:style:settings:outDir:overrides:) -> [URL]` (overrides param added in Task 3); `Recorder.record(target:seconds:outBundle:appVersion:createdISO:)` + `ResolvedTarget` (both `@available(macOS 12.3)`).

---

### Task 1: Package target + scaffold

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ShortsCastEditor/ShortsCastEditor.swift`
- Test: `Tests/ShortsCastEditorTests/ScaffoldTests.swift`

**Interfaces:**
- Consumes: the three existing libraries.
- Produces: library product/target `ShortsCastEditor`, test target `ShortsCastEditorTests`, marker `ShortsCastEditor.version: String`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/ScaffoldTests.swift
import XCTest
@testable import ShortsCastEditor

final class ScaffoldTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(ShortsCastEditor.version.isEmpty)
    }
}
```

- [ ] **Step 2: Update the manifest**

Add the product and targets (keep all existing entries). In `products`:
```swift
        .library(name: "ShortsCastEditor", targets: ["ShortsCastEditor"]),
```
In `targets`:
```swift
        .target(name: "ShortsCastEditor", dependencies: ["ShortsCastCore", "ShortsCastCapture", "ShortsCastRender"]),
        .testTarget(name: "ShortsCastEditorTests", dependencies: ["ShortsCastEditor"]),
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ScaffoldTests`
Expected: FAIL — `ShortsCastEditor` module does not exist.

- [ ] **Step 4: Create the marker**

```swift
// Sources/ShortsCastEditor/ShortsCastEditor.swift
import Foundation

public enum ShortsCastEditor {
    public static let version = "0.1.0"
}
```

- [ ] **Step 5: Run test + build**

Run: `swift test --filter ScaffoldTests` then `swift test`
Expected: scaffold passes; full prior suite (97) + this new test pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ShortsCastEditor Tests/ShortsCastEditorTests
git commit -m "feat: scaffold ShortsCastEditor library"
```

---

### Task 2: Make AutoDirectorSettings & SegmentOverride Codable (Core)

**Files:**
- Modify: `Sources/ShortsCastCore/AutoDirector/AutoDirectorSettings.swift`
- Modify: `Sources/ShortsCastCore/AutoDirector/SegmentOverride.swift`
- Test: `Tests/ShortsCastCoreTests/CodableConformanceTests.swift`

**Interfaces:**
- Produces: `AutoDirectorSettings: Codable, Equatable`; `SegmentOverride: Equatable, Codable`. (Both gain synthesized conformances; no field changes.)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCoreTests/CodableConformanceTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class CodableConformanceTests: XCTestCase {
    func test_autoDirectorSettings_roundTripsAndEquates() throws {
        var s = AutoDirectorSettings()
        s.defaultZoom = 3.3
        s.maxZoom = 5.0
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AutoDirectorSettings.self, from: data)
        XCTAssertEqual(decoded, s)
        XCTAssertEqual(decoded.defaultZoom, 3.3, accuracy: 1e-9)
    }
    func test_segmentOverride_roundTrips() throws {
        let o = SegmentOverride(index: 2, zoom: 3.7, center: CGPoint(x: 10, y: 20))
        let decoded = try JSONDecoder().decode(SegmentOverride.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(decoded, o)
        let o2 = SegmentOverride(index: 1, zoom: nil, center: nil)
        let decoded2 = try JSONDecoder().decode(SegmentOverride.self, from: JSONEncoder().encode(o2))
        XCTAssertEqual(decoded2, o2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CodableConformanceTests`
Expected: FAIL — `AutoDirectorSettings`/`SegmentOverride` do not conform to `Codable` (and `AutoDirectorSettings` is not `Equatable`).

- [ ] **Step 3: Add the conformances**

In `AutoDirectorSettings.swift`, change the declaration line:
```swift
public struct AutoDirectorSettings {
```
to:
```swift
public struct AutoDirectorSettings: Codable, Equatable {
```

In `SegmentOverride.swift`, change:
```swift
public struct SegmentOverride: Equatable {
```
to:
```swift
public struct SegmentOverride: Equatable, Codable {
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CodableConformanceTests`
Expected: PASS — both round-trip; settings equates.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCore/AutoDirector/AutoDirectorSettings.swift Sources/ShortsCastCore/AutoDirector/SegmentOverride.swift Tests/ShortsCastCoreTests/CodableConformanceTests.swift
git commit -m "feat: make AutoDirectorSettings and SegmentOverride Codable"
```

---

### Task 3: ExportJob honors overrides (Render)

**Files:**
- Modify: `Sources/ShortsCastRender/ExportJob.swift`
- Test: `Tests/ShortsCastRenderTests/ExportJobOverridesTests.swift`

**Interfaces:**
- Consumes: `SegmentOverride` (now Codable, Task 2).
- Produces: `ExportJob.run(bundleURL:formats:style:settings:outDir:overrides:) -> [URL]` — new trailing `overrides: [SegmentOverride] = []` parameter, threaded into `Director.direct(log:overrides:)`. Default keeps the existing CLI caller working unchanged.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/ExportJobOverridesTests.swift
import XCTest
import AVFoundation
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastRender

final class ExportJobOverridesTests: XCTestCase {
    func test_run_acceptsOverrides_andExports() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ejo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let screen = CGSize(width: 1280, height: 720)
        let raw = tmp.appendingPathComponent("src.mov")
        try TestVideoFactory.writeSolidColor(to: raw, size: screen, seconds: 0.5, fps: 15,
                                             color: RGBA(0, 0.4, 0.9, 1))
        let log = EventLog(duration: 0.5, screenSize: screen,
                           events: [.click(t: 0.2, point: CGPoint(x: 640, y: 360), button: .left)])
        let meta = BundleMeta(targetKind: "display", displayID: 1, scale: 1,
                              captureRect: CGRect(origin: .zero, size: screen),
                              appVersion: "t", created: "2026-06-30T00:00:00Z")
        let bundle = tmp.appendingPathComponent("clip.shortscast")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: raw, to: bundle)

        let out = tmp.appendingPathComponent("out")
        let urls = try ExportJob.run(bundleURL: bundle, formats: [.vertical9x16],
                                     style: .default, settings: AutoDirectorSettings(), outDir: out,
                                     overrides: [SegmentOverride(index: 0, zoom: 3.9)])
        XCTAssertEqual(urls.count, 1)
        let v = AVAsset(url: urls[0]).tracks(withMediaType: .video).first!
        XCTAssertEqual(v.naturalSize.width, 1080, accuracy: 1)
        XCTAssertEqual(v.naturalSize.height, 1920, accuracy: 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExportJobOverridesTests`
Expected: FAIL — `run(...)` has no `overrides:` parameter.

- [ ] **Step 3: Add the parameter**

In `ExportJob.swift`, change the signature and the `direct` call:
```swift
    public static func run(bundleURL: URL, formats: [OutputFormat], style: RenderStyle,
                           settings: AutoDirectorSettings, outDir: URL,
                           overrides: [SegmentOverride] = []) throws -> [URL] {
        let (eventLog, _, rawVideoURL) = try ProjectBundle.read(bundleURL)
        let result = Director(settings: settings).direct(log: eventLog, overrides: overrides)
```
(Leave the rest of the function unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ExportJobOverridesTests`
Expected: PASS. Also run `swift test --filter ExportJobTests` to confirm the existing (default-overrides) caller still passes.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastRender/ExportJob.swift Tests/ShortsCastRenderTests/ExportJobOverridesTests.swift
git commit -m "feat: ExportJob.run accepts segment overrides"
```

---

### Task 4: ProjectEdits (persistence model)

**Files:**
- Create: `Sources/ShortsCastEditor/ProjectEdits.swift`
- Test: `Tests/ShortsCastEditorTests/ProjectEditsTests.swift`

**Interfaces:**
- Consumes: `SegmentOverride`/`AutoDirectorSettings` (Codable, Task 2), `RenderStyle` (Render).
- Produces: `struct ProjectEdits: Codable, Equatable { var overrides: [SegmentOverride]; var style: RenderStyle; var formatName: String; var settings: AutoDirectorSettings }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/ProjectEditsTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastRender
@testable import ShortsCastEditor

final class ProjectEditsTests: XCTestCase {
    func test_roundTrip() throws {
        var settings = AutoDirectorSettings(); settings.defaultZoom = 2.9
        let edits = ProjectEdits(
            overrides: [SegmentOverride(index: 0, zoom: 3.5)],
            style: .default, formatName: "1:1", settings: settings)
        let decoded = try JSONDecoder().decode(ProjectEdits.self, from: JSONEncoder().encode(edits))
        XCTAssertEqual(decoded, edits)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectEditsTests`
Expected: FAIL — `ProjectEdits` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastEditor/ProjectEdits.swift
import Foundation
import ShortsCastCore
import ShortsCastRender

/// The user's non-destructive edits, persisted as `project.json` inside a `.shortscast` bundle.
public struct ProjectEdits: Codable, Equatable {
    public var overrides: [SegmentOverride]
    public var style: RenderStyle
    public var formatName: String
    public var settings: AutoDirectorSettings
    public init(overrides: [SegmentOverride], style: RenderStyle,
                formatName: String, settings: AutoDirectorSettings) {
        self.overrides = overrides; self.style = style
        self.formatName = formatName; self.settings = settings
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProjectEditsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastEditor/ProjectEdits.swift Tests/ShortsCastEditorTests/ProjectEditsTests.swift
git commit -m "feat: add ProjectEdits persistence model"
```

---

### Task 5: FrameSource + AVAssetFrameSource + test support

**Files:**
- Create: `Sources/ShortsCastEditor/FrameSource.swift`
- Create: `Tests/ShortsCastEditorTests/EditorTestSupport.swift`
- Test: `Tests/ShortsCastEditorTests/FrameSourceTests.swift`

**Interfaces:**
- Produces:
  - `protocol FrameSource { func image(at t: Seconds) -> CIImage? }`
  - `final class AVAssetFrameSource: FrameSource { init(url: URL); func image(at t: Seconds) -> CIImage? }` (via `AVAssetImageGenerator`).
  - Test support: `TestVideoFactory.writeSolidColor(to:size:seconds:fps:color:)`, `FakeFrameSource` (returns a fixed `CIImage`), `samplePixel(_:at:exportSize:context:) -> RGBA`, `solidCIImage(_:size:)`, `twoToneCIImage(top:bottom:size:)`, and `makeBundle(in:screen:seconds:fps:color:events:) -> URL` (writes a `.shortscast`).

- [ ] **Step 1: Write the test support helper**

```swift
// Tests/ShortsCastEditorTests/EditorTestSupport.swift
import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
import ShortsCastRender
@testable import ShortsCastEditor

enum TestVideoFactory {
    static func writeSolidColor(to url: URL, size: CGSize, seconds: Double, fps: Int, color: RGBA) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        let image = CIImage(color: color.ciColor).cropped(to: CGRect(origin: .zero, size: size))
        for i in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            ctx.render(image, to: pb!)
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0); writer.finishWriting { sema.signal() }; sema.wait()
    }
}

final class FakeFrameSource: FrameSource {
    let image: CIImage
    init(_ image: CIImage) { self.image = image }
    func image(at t: Seconds) -> CIImage? { image }
}

func solidCIImage(_ color: RGBA, size: CGSize) -> CIImage {
    CIImage(color: color.ciColor).cropped(to: CGRect(origin: .zero, size: size))
}

/// Top half (visual top) = `top`, bottom half = `bottom`. Built via CG so orientation is unambiguous.
func twoToneCIImage(top: RGBA, bottom: RGBA, size: CGSize) -> CIImage {
    let w = Int(size.width), h = Int(size.height)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // CGContext is bottom-left; draw bottom color in lower half, top color in upper half.
    ctx.setFillColor(CGColor(red: CGFloat(bottom.r), green: CGFloat(bottom.g), blue: CGFloat(bottom.b), alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 2))
    ctx.setFillColor(CGColor(red: CGFloat(top.r), green: CGFloat(top.g), blue: CGFloat(top.b), alpha: 1))
    ctx.fill(CGRect(x: 0, y: h / 2, width: w, height: h - h / 2))
    return CIImage(cgImage: ctx.makeImage()!)
}

func samplePixel(_ image: CIImage, at p: CGPoint, exportSize: CGSize, context: CIContext) -> RGBA {
    let cg = context.createCGImage(image, from: CGRect(origin: .zero, size: exportSize))!
    let cs = CGColorSpaceCreateDeviceRGB()
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: -p.x, y: -p.y, width: exportSize.width, height: exportSize.height))
    return RGBA(Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255, Double(px[3]) / 255)
}

/// Writes a `.shortscast` bundle (raw.mov + events.json + meta.json) and returns its URL.
func makeBundle(in dir: URL, screen: CGSize, seconds: Double, fps: Int, color: RGBA,
                events: [RecordingEvent]) throws -> URL {
    let raw = dir.appendingPathComponent("src.mov")
    try TestVideoFactory.writeSolidColor(to: raw, size: screen, seconds: seconds, fps: fps, color: color)
    let log = EventLog(duration: seconds, screenSize: screen, events: events)
    let meta = BundleMeta(targetKind: "display", displayID: 1, scale: 1,
                          captureRect: CGRect(origin: .zero, size: screen),
                          appVersion: "test", created: "2026-06-30T00:00:00Z")
    let bundle = dir.appendingPathComponent("clip.shortscast")
    try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: raw, to: bundle)
    return bundle
}
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/FrameSourceTests.swift
import XCTest
import AVFoundation
import CoreImage
import CoreGraphics
import ShortsCastRender
@testable import ShortsCastEditor

final class FrameSourceTests: XCTestCase {
    func test_avAssetFrameSource_returnsFrame() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let raw = tmp.appendingPathComponent("v.mov")
        let size = CGSize(width: 320, height: 240)
        try TestVideoFactory.writeSolidColor(to: raw, size: size, seconds: 1.0, fps: 15, color: RGBA(0, 1, 0, 1))

        let src = AVAssetFrameSource(url: raw)
        let img = src.image(at: 0.5)
        XCTAssertNotNil(img)
        XCTAssertEqual(img!.extent.width, 320, accuracy: 2)
        XCTAssertEqual(img!.extent.height, 240, accuracy: 2)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter FrameSourceTests`
Expected: FAIL — `AVAssetFrameSource` not defined.

- [ ] **Step 4: Write minimal implementation**

```swift
// Sources/ShortsCastEditor/FrameSource.swift
import Foundation
import AVFoundation
import CoreImage
import CoreMedia
import ShortsCastCore

/// Supplies a source video frame (as a CIImage) at a given recording time.
public protocol FrameSource {
    func image(at t: Seconds) -> CIImage?
}

/// Decodes frames from a `.mov` via AVAssetImageGenerator (upright CGImage -> CIImage).
public final class AVAssetFrameSource: FrameSource {
    private let generator: AVAssetImageGenerator

    public init(url: URL) {
        let asset = AVAsset(url: url)
        let g = AVAssetImageGenerator(asset: asset)
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        g.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        generator = g
    }

    public func image(at t: Seconds) -> CIImage? {
        let time = CMTime(seconds: max(0, t), preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return CIImage(cgImage: cg)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter FrameSourceTests`
Expected: PASS — a 320×240 frame is returned at t=0.5.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortsCastEditor/FrameSource.swift Tests/ShortsCastEditorTests/EditorTestSupport.swift Tests/ShortsCastEditorTests/FrameSourceTests.swift
git commit -m "feat: add FrameSource + AVAssetFrameSource and editor test support"
```

---

### Task 6: EditorModel core — open, regenerate, segments/duration

**Files:**
- Create: `Sources/ShortsCastEditor/EditorModel.swift`
- Test: `Tests/ShortsCastEditorTests/EditorModelOpenTests.swift`

**Interfaces:**
- Consumes: `FrameSource`/`AVAssetFrameSource` (Task 5), `ProjectBundle`/`EventLog` (capture), `Director`/`DirectorResult`/`FocusSegment`/`SegmentOverride`/`AutoDirectorSettings`/`OutputFormat` (core), `RenderStyle`/`FrameCompositor` (render).
- Produces: `final class EditorModel: ObservableObject` with the full `@Published` state block, `enum EditorError: Error { case notOpen }`, `open(_:) throws`, `private regenerate()`, `private invalidateCompositor()`, `var segments`, `var duration`. The stored props `settings`/`style`/`format` carry `didSet` hooks (regenerate / invalidate); `overrides` is `private(set)`. (Editing methods, preview, persistence, export, record arrive in later tasks; this task delivers a model you can open and inspect.)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/EditorModelOpenTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastEditor

final class EditorModelOpenTests: XCTestCase {
    func test_open_directsAndExposesSegmentsAndDuration() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("em-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let screen = CGSize(width: 1280, height: 720)
        let bundle = try makeBundle(in: tmp, screen: screen, seconds: 1.0, fps: 15, color: RGBA(0, 0.5, 1, 1),
                                    events: [.click(t: 0.3, point: CGPoint(x: 600, y: 300), button: .left),
                                             .click(t: 0.35, point: CGPoint(x: 610, y: 305), button: .left)])
        let model = EditorModel()
        try model.open(bundle)
        XCTAssertNotNil(model.result)
        XCTAssertEqual(model.duration, 1.0, accuracy: 1e-6)
        XCTAssertEqual(model.screenSize, screen)
        XCTAssertEqual(model.segments.count, 1) // two nearby clicks cluster into one focus segment
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EditorModelOpenTests`
Expected: FAIL — `EditorModel` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastEditor/EditorModel.swift
import Foundation
import Combine
import CoreGraphics
import CoreImage
import ShortsCastCore
import ShortsCastCapture
import ShortsCastRender

public final class EditorModel: ObservableObject {
    public enum EditorError: Error { case notOpen }

    @Published public private(set) var bundleURL: URL?
    @Published public private(set) var eventLog: EventLog?
    @Published public private(set) var rawVideoURL: URL?
    @Published public private(set) var screenSize: CGSize = .zero
    @Published public private(set) var overrides: [SegmentOverride] = []
    @Published public private(set) var result: DirectorResult?
    @Published public var selectedSegment: Int?

    @Published public var settings = AutoDirectorSettings() { didSet { if !isLoading { regenerate() } } }
    @Published public var style = RenderStyle.default { didSet { if !isLoading { invalidateCompositor() } } }
    @Published public var format = OutputFormat.vertical9x16 { didSet { if !isLoading { invalidateCompositor() } } }

    var frameSource: FrameSource?          // settable for tests
    private var cachedCompositor: FrameCompositor?
    private var isLoading = false

    public init() {}

    public var segments: [FocusSegment] { result?.segments ?? [] }
    public var duration: Seconds { eventLog?.duration ?? 0 }

    public func open(_ url: URL) throws {
        let (log, _, raw) = try ProjectBundle.read(url)
        isLoading = true
        bundleURL = url
        eventLog = log
        rawVideoURL = raw
        screenSize = log.screenSize
        overrides = []
        settings = AutoDirectorSettings()
        style = .default
        format = .vertical9x16
        frameSource = AVAssetFrameSource(url: raw)
        cachedCompositor = nil
        isLoading = false
        regenerate()
    }

    func regenerate() {
        guard let log = eventLog else { return }
        result = Director(settings: settings).direct(log: log, overrides: overrides)
    }

    func invalidateCompositor() { cachedCompositor = nil }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EditorModelOpenTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastEditor/EditorModel.swift Tests/ShortsCastEditorTests/EditorModelOpenTests.swift
git commit -m "feat: EditorModel open + regenerate + segments/duration"
```

---

### Task 7: EditorModel editing (overrides + zoom settings)

**Files:**
- Modify: `Sources/ShortsCastEditor/EditorModel.swift`
- Test: `Tests/ShortsCastEditorTests/EditorModelEditingTests.swift`

**Interfaces:**
- Consumes: the Task 6 model + `applyOverrides` semantics.
- Produces: `setZoom(segment index: Int, zoom: CGFloat)` (upsert override for that index, then `regenerate()`), `clearOverride(segment index: Int)` (remove + `regenerate()`). (Global zoom changes go through `settings.defaultZoom`/`settings.maxZoom`, whose `didSet` already regenerates; format/style via the property setters.)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/EditorModelEditingTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastEditor

final class EditorModelEditingTests: XCTestCase {
    private func openedModel() throws -> EditorModel {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("eme-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: CGSize(width: 1280, height: 720), seconds: 1.0, fps: 15,
                                    color: RGBA(0, 0.5, 1, 1),
                                    events: [.click(t: 0.3, point: CGPoint(x: 600, y: 300), button: .left),
                                             .click(t: 0.35, point: CGPoint(x: 610, y: 305), button: .left)])
        let m = EditorModel(); try m.open(bundle); return m
    }

    func test_setZoom_overridesSegmentZoom() throws {
        let m = try openedModel()
        XCTAssertEqual(m.segments.count, 1)
        m.setZoom(segment: 0, zoom: 3.9)
        XCTAssertEqual(m.segments[0].zoom, 3.9, accuracy: 1e-6)
        XCTAssertEqual(m.overrides.count, 1)
    }

    func test_setZoom_isIdempotentPerSegment() throws {
        let m = try openedModel()
        m.setZoom(segment: 0, zoom: 3.0)
        m.setZoom(segment: 0, zoom: 2.2)
        XCTAssertEqual(m.overrides.count, 1)          // replaced, not duplicated
        XCTAssertEqual(m.segments[0].zoom, 2.2, accuracy: 1e-6)
    }

    func test_clearOverride_reverts() throws {
        let m = try openedModel()
        let original = m.segments[0].zoom
        m.setZoom(segment: 0, zoom: 3.9)
        m.clearOverride(segment: 0)
        XCTAssertTrue(m.overrides.isEmpty)
        XCTAssertEqual(m.segments[0].zoom, original, accuracy: 1e-6)
    }

    func test_maxZoomSetting_capsGeneratedZoom() throws {
        let m = try openedModel()
        m.settings.defaultZoom = 5.0
        m.settings.maxZoom = 2.0   // didSet regenerates; clamps generated zoom
        XCTAssertLessThanOrEqual(m.segments[0].zoom, 2.0 + 1e-6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EditorModelEditingTests`
Expected: FAIL — `setZoom`/`clearOverride` not defined.

- [ ] **Step 3: Add the editing methods**

Add to `EditorModel` (inside the class, after `regenerate()`):
```swift
    public func setZoom(segment index: Int, zoom: CGFloat) {
        overrides.removeAll { $0.index == index }
        overrides.append(SegmentOverride(index: index, zoom: zoom))
        regenerate()
    }

    public func clearOverride(segment index: Int) {
        overrides.removeAll { $0.index == index }
        regenerate()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EditorModelEditingTests`
Expected: PASS — all four cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastEditor/EditorModel.swift Tests/ShortsCastEditorTests/EditorModelEditingTests.swift
git commit -m "feat: EditorModel per-segment zoom editing"
```

---

### Task 8: EditorModel persistence (project.json)

**Files:**
- Modify: `Sources/ShortsCastEditor/EditorModel.swift`
- Test: `Tests/ShortsCastEditorTests/EditorModelPersistenceTests.swift`

**Interfaces:**
- Consumes: `ProjectEdits` (Task 4).
- Produces: `currentEdits() -> ProjectEdits`; `save() throws` (writes `<bundle>/project.json`); and `open(_:)` is extended to load `project.json` when present (applying overrides/style/format/settings before regenerating; tolerant of a missing/garbled file). Unknown `formatName` → `.vertical9x16`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/EditorModelPersistenceTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastRender
@testable import ShortsCastEditor

final class EditorModelPersistenceTests: XCTestCase {
    func test_saveThenReopen_restoresEdits() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("emp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: CGSize(width: 1280, height: 720), seconds: 1.0, fps: 15,
                                    color: RGBA(0, 0.5, 1, 1),
                                    events: [.click(t: 0.3, point: CGPoint(x: 600, y: 300), button: .left),
                                             .click(t: 0.35, point: CGPoint(x: 610, y: 305), button: .left)])
        let m = EditorModel(); try m.open(bundle)
        m.setZoom(segment: 0, zoom: 3.3)
        m.format = .square1x1
        m.settings.defaultZoom = 2.8
        try m.save()

        let m2 = EditorModel(); try m2.open(bundle)
        XCTAssertEqual(m2.overrides, [SegmentOverride(index: 0, zoom: 3.3)])
        XCTAssertEqual(m2.format.name, "1:1")
        XCTAssertEqual(m2.settings.defaultZoom, 2.8, accuracy: 1e-6)
        XCTAssertEqual(m2.segments[0].zoom, 3.3, accuracy: 1e-6) // override re-applied
    }

    func test_open_toleratesMissingProjectJSON() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("emp2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: CGSize(width: 1280, height: 720), seconds: 1.0, fps: 15,
                                    color: RGBA(0, 0.5, 1, 1),
                                    events: [.click(t: 0.3, point: CGPoint(x: 600, y: 300), button: .left)])
        let m = EditorModel(); try m.open(bundle) // no project.json present
        XCTAssertTrue(m.overrides.isEmpty)
        XCTAssertEqual(m.format.name, "9:16")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EditorModelPersistenceTests`
Expected: FAIL — `save`/`currentEdits` not defined (and `open` doesn't load edits).

- [ ] **Step 3: Add persistence**

Add to `EditorModel`:
```swift
    public func currentEdits() -> ProjectEdits {
        ProjectEdits(overrides: overrides, style: style, formatName: format.name, settings: settings)
    }

    public func save() throws {
        guard let url = bundleURL else { throw EditorError.notOpen }
        let data = try JSONEncoder().encode(currentEdits())
        try data.write(to: url.appendingPathComponent("project.json"))
    }

    private func loadEdits(from bundle: URL) -> ProjectEdits? {
        let p = bundle.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: p) else { return nil }
        return try? JSONDecoder().decode(ProjectEdits.self, from: data)
    }
```

In `open(_:)`, replace the default-state block:
```swift
        overrides = []
        settings = AutoDirectorSettings()
        style = .default
        format = .vertical9x16
```
with:
```swift
        if let edits = loadEdits(from: url) {
            overrides = edits.overrides
            settings = edits.settings
            style = edits.style
            format = OutputFormat.all.first { $0.name == edits.formatName } ?? .vertical9x16
        } else {
            overrides = []
            settings = AutoDirectorSettings()
            style = .default
            format = .vertical9x16
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EditorModelPersistenceTests`
Expected: PASS — both cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastEditor/EditorModel.swift Tests/ShortsCastEditorTests/EditorModelPersistenceTests.swift
git commit -m "feat: EditorModel project.json persistence"
```

---

### Task 9: EditorModel preview

**Files:**
- Modify: `Sources/ShortsCastEditor/EditorModel.swift`
- Test: `Tests/ShortsCastEditorTests/EditorModelPreviewTests.swift`

**Interfaces:**
- Consumes: `FrameCompositor` (render), the cached-compositor invalidation from Task 6.
- Produces: `previewImage(at t: Seconds) -> CGImage?` — composites the source frame (from `frameSource`) at `t` using a lazily-built, cached `FrameCompositor` (rebuilt after `style`/`format` change), returning a `CGImage` at `format.exportSize`; nil if not open or no source frame. Adds a private `currentCompositor() -> FrameCompositor`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/EditorModelPreviewTests.swift
import XCTest
import CoreImage
import CoreGraphics
import ShortsCastCore
import ShortsCastRender
@testable import ShortsCastEditor

final class EditorModelPreviewTests: XCTestCase {
    private func openedModel(screen: CGSize) throws -> EditorModel {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("empv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: screen, seconds: 1.0, fps: 15, color: RGBA(0, 1, 0, 1),
                                    events: [.click(t: 0.3, point: CGPoint(x: 600, y: 300), button: .left)])
        let m = EditorModel(); try m.open(bundle); return m
    }

    func test_previewImage_compositesBackgroundAndContent() throws {
        let screen = CGSize(width: 1080, height: 1080)
        let m = try openedModel(screen: screen)
        m.format = .square1x1
        m.style = RenderStyle(background: .solid(RGBA(1, 0, 0, 1)), cornerRadius: 0, shadowOpacity: 0,
                              shadowBlur: 0, shadowOffsetY: 0, paddingFraction: 0.1, cursorRadius: 1,
                              cursorColor: RGBA(0, 0, 0, 1), rippleDuration: 0.5, rippleMaxRadius: 1)
        m.frameSource = FakeFrameSource(solidCIImage(RGBA(0, 1, 0, 1), size: screen)) // green source
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])

        let cg = m.previewImage(at: 0.0)
        XCTAssertNotNil(cg)
        let img = CIImage(cgImage: cg!)
        let center = samplePixel(img, at: CGPoint(x: 540, y: 540), exportSize: m.format.exportSize, context: ctx)
        XCTAssertEqual(center.g, 1, accuracy: 0.2)   // content (green) at center
        let edge = samplePixel(img, at: CGPoint(x: 5, y: 540), exportSize: m.format.exportSize, context: ctx)
        XCTAssertEqual(edge.r, 1, accuracy: 0.2)      // background (red) at edge
    }

    func test_previewImage_noVerticalFlipThroughEditor() throws {
        let screen = CGSize(width: 1080, height: 1080)
        let m = try openedModel(screen: screen)
        m.format = .square1x1
        m.style = RenderStyle(background: .solid(RGBA(0, 0, 1, 1)), cornerRadius: 0, shadowOpacity: 0,
                              shadowBlur: 0, shadowOffsetY: 0, paddingFraction: 0, cursorRadius: 1,
                              cursorColor: RGBA(0, 0, 0, 1), rippleDuration: 0.5, rippleMaxRadius: 1)
        // visual top red, bottom green
        m.frameSource = FakeFrameSource(twoToneCIImage(top: RGBA(1, 0, 0, 1), bottom: RGBA(0, 1, 0, 1), size: screen))
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        let cg = m.previewImage(at: 0.0)!
        let img = CIImage(cgImage: cg)
        let top = samplePixel(img, at: CGPoint(x: 540, y: 1000), exportSize: m.format.exportSize, context: ctx)
        let bottom = samplePixel(img, at: CGPoint(x: 540, y: 80), exportSize: m.format.exportSize, context: ctx)
        XCTAssertEqual(top.r, 1, accuracy: 0.25)      // source visual-top -> output visual-top
        XCTAssertEqual(bottom.g, 1, accuracy: 0.25)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EditorModelPreviewTests`
Expected: FAIL — `previewImage` not defined.

- [ ] **Step 3: Add preview**

Add to `EditorModel`:
```swift
    private func currentCompositor() -> FrameCompositor {
        if let c = cachedCompositor { return c }
        let c = FrameCompositor(style: style, format: format, screenSize: screenSize)
        cachedCompositor = c
        return c
    }

    public func previewImage(at t: Seconds) -> CGImage? {
        guard let result = result, let source = frameSource?.image(at: t) else { return nil }
        let crop = Director(settings: settings).cropRect(result, at: t, format: format, screen: screenSize)
        let comp = currentCompositor()
        let composed = comp.composite(source: source, crop: crop, time: t, cursor: result.cursor)
        return comp.context.createCGImage(composed, from: CGRect(origin: .zero, size: format.exportSize))
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EditorModelPreviewTests`
Expected: PASS — content/background placement and no vertical flip.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastEditor/EditorModel.swift Tests/ShortsCastEditorTests/EditorModelPreviewTests.swift
git commit -m "feat: EditorModel live preview compositing"
```

---

### Task 10: EditorModel export

**Files:**
- Modify: `Sources/ShortsCastEditor/EditorModel.swift`
- Test: `Tests/ShortsCastEditorTests/EditorModelExportTests.swift`

**Interfaces:**
- Consumes: `ExportJob.run(...:overrides:)` (Task 3).
- Produces: `export(formats: [OutputFormat], outDir: URL) throws -> [URL]` — calls `ExportJob.run` with the model's `style`, `settings`, and `overrides`; throws `EditorError.notOpen` if no bundle is open.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/EditorModelExportTests.swift
import XCTest
import AVFoundation
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastEditor

final class EditorModelExportTests: XCTestCase {
    func test_export_writesOneMP4PerFormat() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("emx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bundle = try makeBundle(in: tmp, screen: CGSize(width: 1280, height: 720), seconds: 0.5, fps: 15,
                                    color: RGBA(0, 0.5, 1, 1),
                                    events: [.click(t: 0.2, point: CGPoint(x: 600, y: 300), button: .left)])
        let m = EditorModel(); try m.open(bundle)
        m.setZoom(segment: 0, zoom: 3.5) // exercise override path through export

        let outDir = tmp.appendingPathComponent("out")
        let urls = try m.export(formats: [.vertical9x16, .square1x1], outDir: outDir)
        XCTAssertEqual(urls.count, 2)
        for u in urls { XCTAssertTrue(FileManager.default.fileExists(atPath: u.path)) }
        let v = AVAsset(url: urls[0]).tracks(withMediaType: .video).first!
        XCTAssertEqual(v.naturalSize.width, 1080, accuracy: 1)
        XCTAssertEqual(v.naturalSize.height, 1920, accuracy: 1)
    }

    func test_export_throwsWhenNotOpen() {
        let m = EditorModel()
        XCTAssertThrowsError(try m.export(formats: [.vertical9x16], outDir: URL(fileURLWithPath: "/tmp/x")))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EditorModelExportTests`
Expected: FAIL — `export` not defined.

- [ ] **Step 3: Add export**

Add to `EditorModel`:
```swift
    public func export(formats: [OutputFormat], outDir: URL) throws -> [URL] {
        guard let url = bundleURL else { throw EditorError.notOpen }
        return try ExportJob.run(bundleURL: url, formats: formats, style: style,
                                 settings: settings, outDir: outDir, overrides: overrides)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EditorModelExportTests`
Expected: PASS — two MP4s with correct dimensions; not-open throws.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastEditor/EditorModel.swift Tests/ShortsCastEditorTests/EditorModelExportTests.swift
git commit -m "feat: EditorModel export honoring overrides"
```

---

### Task 11: EditorModel record orchestration (macOS 12.3)

**Files:**
- Modify: `Sources/ShortsCastEditor/EditorModel.swift`

**Interfaces:**
- Consumes: `Recorder.record(target:seconds:outBundle:appVersion:createdISO:)` + `ResolvedTarget` (capture, `@available(macOS 12.3)`).
- Produces: `@available(macOS 12.3, *) func record(target: ResolvedTarget, seconds: Double, outBundle: URL, appVersion: String, createdISO: String) async throws` — records, then `open(outBundle)`. Not unit-tested (capture is broken on macOS 12.6); verified by `swift build` and in Plan 5 on macOS 13+.

- [ ] **Step 1: Add the method**

Add to `EditorModel`:
```swift
    @available(macOS 12.3, *)
    public func record(target: ResolvedTarget, seconds: Double, outBundle: URL,
                       appVersion: String, createdISO: String) async throws {
        _ = try await Recorder.record(target: target, seconds: seconds, outBundle: outBundle,
                                      appVersion: appVersion, createdISO: createdISO)
        try open(outBundle)
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: succeeds (the `@available` method type-checks against `Recorder`/`ResolvedTarget`).

- [ ] **Step 3: Run the full suite**

Run: `swift test`
Expected: every editor + prior test passes (no new test for `record`, by design).

- [ ] **Step 4: Commit**

```bash
git add Sources/ShortsCastEditor/EditorModel.swift
git commit -m "feat: EditorModel record orchestration (macOS 12.3)"
```

---

## Self-Review

**Spec coverage:**
- `ShortsCastEditor` target → Task 1.
- Core Codable tweaks (`AutoDirectorSettings`, `SegmentOverride`) → Task 2; `ExportJob` overrides param → Task 3.
- `ProjectEdits` → Task 4. `FrameSource`/`AVAssetFrameSource` → Task 5.
- `EditorModel` open/regenerate/segments/duration → Task 6; editing (zoom override, clear, global zoom via settings) → Task 7; persistence (project.json save/load) → Task 8; preview → Task 9; export honoring overrides → Task 10; record orchestration → Task 11.
- Format/style edits realized as the `@Published` property setters with `didSet` invalidation (spec's `setFormat`/`setStyle`); selection via `selectedSegment` (spec's `selectSegment`); global zoom via `settings.defaultZoom`/`maxZoom` (spec's `setDefaultZoom`/`setMaxZoom`) — all documented in Tasks 6/7.
- Testing strategy (synthetic video, fake FrameSource, pixel assertions, two-tone orientation, export integration; record excluded) → Tasks 5-10.

**Placeholder scan:** No TBD/TODO/"handle edge cases"; complete Swift in every code step. Test support (Task 5) is full code, not a stub.

**Type consistency:** `EditorModel` property names (`settings`/`style`/`format`/`overrides`/`result`/`selectedSegment`/`screenSize`/`frameSource`) and methods (`open`/`regenerate`/`setZoom(segment:zoom:)`/`clearOverride(segment:)`/`currentEdits`/`save`/`previewImage(at:)`/`export(formats:outDir:)`/`record(...)`) are introduced once and reused consistently across Tasks 6-11. `ProjectEdits` fields match `currentEdits()` and the load path (Tasks 4, 8). `ExportJob.run(...:overrides:)` signature matches between Tasks 3 and 10. `FrameSource.image(at:)` matches between Tasks 5 and 9. Reused core/capture/render signatures match the Global Constraints.

## Notes for Plan 5 (SwiftUI shell)

- Plan 5 builds the SwiftUI app (`@main`) + `.app` bundle, binding views to this `EditorModel`: preview canvas ← `previewImage(at:)`; timeline ← `segments`/`selectedSegment`/`setZoom`; inspector ← `style`/`format`/`settings`; buttons ← `export`/`record`/`save`.
- Live capture (`record`) and the aesthetic export eyeball get verified there on macOS 13+ (the `.app` gets a stable TCC identity, extending `Scripts/make-app.sh`).
