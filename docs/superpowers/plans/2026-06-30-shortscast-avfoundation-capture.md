# ShortsCast AVFoundation Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ScreenCaptureKit capture backend (which delivers no frames on macOS 12.6) with AVFoundation's `AVCaptureScreenInput`, so live screen recording — and the full Record → edit → export loop — works on this machine.

**Architecture:** Swap only the frame source: a new `AVScreenCaptureSession` (AVCaptureScreenInput → AVCaptureVideoDataOutput → AVAssetWriter) feeds the existing, unchanged pipeline (CGEventTap, EventLogBuilder, ProjectBundle). `TargetResolver` is rewritten on CoreGraphics (no SCK) with a pure, tested `WindowFinder` helper. AVCapture sample PTS is on the host (mach) clock, so event↔video timestamp sync is preserved. SCK and its `@available(macOS 12.3)` guards are removed.

**Tech Stack:** Swift 5.7 (Xcode 14.2), AVFoundation, CoreMedia, CoreVideo, CoreGraphics, XCTest.

## Global Constraints

- Swift tools `5.7`; package platform floor `.macOS(.v12)`. Capture has **no** runtime availability gate after this plan (`AVCaptureScreenInput` is macOS 10.7+).
- Frame source is `AVCaptureScreenInput`; `capturesCursor = false` (compositor draws the synthetic cursor). No CoreImage crop in capture — `cropRect` produces already-cropped frames.
- Event↔video clock: AVCapture sample PTS uses the host-time clock (mach); event timestamps use `machNowSeconds()` (mach). They share an epoch; `EventLogBuilder.build(firstFrameT:endT:)` rebases to t=0 unchanged.
- Three targets: display (`displayID`), region (`AVCaptureScreenInput.cropRect`), window (CGWindowList bounds → crop to that rect; window bounds captured once at resolve time).
- Unchanged: `CaptureGeometry`, `EventMapper`, `EventLogBuilder`, `EventTap`, `ProjectBundle`, `CLIOptions`, and all of Core/Render/Editor logic (apart from removing one now-unneeded `@available`).
- Reused (verbatim): `machNowSeconds()`; `CaptureGeometry(captureRect:scale:)` + `.pixelSize`; `EventLogBuilder(geometry:cursorHz:)`/`.add`/`.build(firstFrameT:endT:)`; `EventTap(handler:)`/`.start()`/`.stop()`; `ProjectBundle.write(eventLog:meta:rawVideo:to:)`; `BundleMeta(targetKind:displayID:scale:captureRect:appVersion:created:)` (`displayID: UInt32?`); `EventLog`.

---

### Task 1: WindowFinder (pure window selection)

**Files:**
- Create: `Sources/ShortsCastCapture/WindowFinder.swift`
- Test: `Tests/ShortsCastCaptureTests/WindowFinderTests.swift`

**Interfaces:**
- Produces: `enum WindowFinder { static func selectBounds(in windows: [[String: Any]], matching query: String) -> CGRect? }` — matches a CGWindowList-shaped entry by owner name (`kCGWindowOwnerName` case-insensitively contains `query`) or window number (`kCGWindowNumber` equals `query`); returns its `kCGWindowBounds` as a `CGRect`; nil if none match or bounds are missing.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastCaptureTests/WindowFinderTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCapture

final class WindowFinderTests: XCTestCase {
    private func win(owner: String, number: Int, bounds: [String: Any]?) -> [String: Any] {
        var d: [String: Any] = [kCGWindowOwnerName as String: owner, kCGWindowNumber as String: number]
        if let b = bounds { d[kCGWindowBounds as String] = b }
        return d
    }
    private let safariBounds: [String: Any] = ["X": 100, "Y": 50, "Width": 800, "Height": 600]

    func test_matchesByOwnerNameContains() {
        let list = [win(owner: "Finder", number: 1, bounds: ["X": 0, "Y": 0, "Width": 10, "Height": 10]),
                    win(owner: "Safari", number: 42, bounds: safariBounds)]
        let r = WindowFinder.selectBounds(in: list, matching: "saf")
        XCTAssertEqual(r, CGRect(x: 100, y: 50, width: 800, height: 600))
    }
    func test_matchesByWindowNumber() {
        let list = [win(owner: "Safari", number: 42, bounds: safariBounds)]
        XCTAssertEqual(WindowFinder.selectBounds(in: list, matching: "42"),
                       CGRect(x: 100, y: 50, width: 800, height: 600))
    }
    func test_noMatchReturnsNil() {
        let list = [win(owner: "Safari", number: 42, bounds: safariBounds)]
        XCTAssertNil(WindowFinder.selectBounds(in: list, matching: "Xcode"))
    }
    func test_matchButMissingBoundsReturnsNil() {
        let list = [win(owner: "Safari", number: 42, bounds: nil)]
        XCTAssertNil(WindowFinder.selectBounds(in: list, matching: "Safari"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WindowFinderTests`
Expected: FAIL — `WindowFinder` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastCapture/WindowFinder.swift
import Foundation
import CoreGraphics

/// Pure selection over a CGWindowList-shaped array: find a window's on-screen bounds by
/// owner name (case-insensitive contains) or window number.
public enum WindowFinder {
    public static func selectBounds(in windows: [[String: Any]], matching query: String) -> CGRect? {
        for w in windows {
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            let numberMatches = (w[kCGWindowNumber as String] as? NSNumber).map { "\($0.intValue)" == query } ?? false
            guard owner.localizedCaseInsensitiveContains(query) || numberMatches else { continue }
            if let rect = boundsRect(w[kCGWindowBounds as String]) { return rect }
        }
        return nil
    }

    private static func boundsRect(_ any: Any?) -> CGRect? {
        guard let d = any as? [String: Any] else { return nil }
        func num(_ k: String) -> CGFloat? { (d[k] as? NSNumber).map { CGFloat(truncating: $0) } }
        guard let x = num("X"), let y = num("Y"), let w = num("Width"), let h = num("Height") else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WindowFinderTests`
Expected: PASS — all four cases. (Int literals in the synthetic dicts bridge to `NSNumber`, matching real CGWindowList values.)

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastCapture/WindowFinder.swift Tests/ShortsCastCaptureTests/WindowFinderTests.swift
git commit -m "feat: add WindowFinder window-bounds selection"
```

---

### Task 2: AVFoundation backend swap (session + resolver + recorder)

**Files:**
- Create: `Sources/ShortsCastCapture/AVScreenCaptureSession.swift`
- Rewrite: `Sources/ShortsCastCapture/TargetResolver.swift`
- Rewrite: `Sources/ShortsCastCapture/Recorder.swift`
- Delete: `Sources/ShortsCastCapture/ScreenCaptureSession.swift`
- Modify: `Sources/shortscast-rec/main.swift` (drop `await` on the now-synchronous `TargetResolver.resolve`)

**Interfaces:**
- Consumes: `WindowFinder` (Task 1), `machNowSeconds()`, `CaptureGeometry`, `EventLogBuilder`, `EventTap`, `ProjectBundle`/`BundleMeta`, `EventLog`.
- Produces:
  - `final class AVScreenCaptureSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate` with `init(outputURL:displayID:cropRect:pixelSize:)`, `start() async throws`, `stop() async -> (firstFrameT: Double, endT: Double)`, `var firstFramePTSSeconds: Double?`, `var writerError: Error?`.
  - `struct ResolvedTarget { let kind: String; let displayID: CGDirectDisplayID; let captureRectPoints: CGRect; let scale: CGFloat; let cropRect: CGRect? }` (no SCK types, no `@available`).
  - `enum TargetResolver { static func resolve(displayIndex: Int?, windowQuery: String?, region: CGRect?) throws -> ResolvedTarget }` (synchronous, CoreGraphics-based, no `@available`).
  - `enum Recorder { enum RecorderError; struct Result; static func record(target:seconds:outBundle:appVersion:createdISO:) async throws -> Result }` (no `@available`).
- This task is an atomic backend swap: there are no unit tests for these OS-bound types; the deliverable is that the **package builds** and the **full existing suite still passes** (the pure capture tests are unchanged). It is verified live in Task 4.

- [ ] **Step 1: Create AVScreenCaptureSession**

```swift
// Sources/ShortsCastCapture/AVScreenCaptureSession.swift
import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics

/// Captures a display (optionally cropped) via AVCaptureScreenInput and writes H.264 .mov,
/// anchoring t=0 on the first frame. Replaces the ScreenCaptureKit session.
public final class AVScreenCaptureSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public enum CaptureError: Error { case inputUnavailable, cannotAddInput, cannotAddOutput, writerSetupFailed }

    private let outputURL: URL
    private let displayID: CGDirectDisplayID
    private let cropRect: CGRect?
    private let pixelSize: CGSize

    private let session = AVCaptureSession()
    private let sampleQueue = DispatchQueue(label: "shortscast.avcapture.samples")
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    public private(set) var firstFramePTSSeconds: Double?
    public private(set) var writerError: Error?

    public init(outputURL: URL, displayID: CGDirectDisplayID, cropRect: CGRect?, pixelSize: CGSize) {
        self.outputURL = outputURL; self.displayID = displayID
        self.cropRect = cropRect; self.pixelSize = pixelSize
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

    public func start() async throws {
        try makeWriter()
        guard let screenInput = AVCaptureScreenInput(displayID: displayID) else { throw CaptureError.inputUnavailable }
        screenInput.capturesCursor = false
        screenInput.minFrameDuration = CMTime(value: 1, timescale: 60)
        if let crop = cropRect { screenInput.cropRect = crop }

        session.beginConfiguration()
        session.sessionPreset = .high
        guard session.canAddInput(screenInput) else { session.commitConfiguration(); throw CaptureError.cannotAddInput }
        session.addInput(screenInput)
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        out.alwaysDiscardsLateVideoFrames = false
        out.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(out) else { session.commitConfiguration(); throw CaptureError.cannotAddOutput }
        session.addOutput(out)
        session.commitConfiguration()
        session.startRunning()
    }

    public func stop() async -> (firstFrameT: Double, endT: Double) {
        session.stopRunning()
        // Drain in-flight sample callbacks before reading state they write.
        await withCheckedContinuation { cont in sampleQueue.async { cont.resume() } }
        let end = machNowSeconds()
        if let w = writer, w.status == .writing {
            input?.markAsFinished()
            await w.finishWriting()
            writerError = w.error
        } else {
            writerError = writer?.error
        }
        return (firstFramePTSSeconds ?? end, end)
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let writer = writer, let input = input, let adaptor = adaptor,
              CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            firstFramePTSSeconds = CMTimeGetSeconds(pts)
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        adaptor.append(imageBuffer, withPresentationTime: pts)
    }
}
```

- [ ] **Step 2: Rewrite TargetResolver**

Replace the ENTIRE contents of `Sources/ShortsCastCapture/TargetResolver.swift` with:
```swift
// Sources/ShortsCastCapture/TargetResolver.swift
import Foundation
import CoreGraphics

/// A resolved capture target for AVCaptureScreenInput.
public struct ResolvedTarget {
    public let kind: String                 // "display" | "region" | "window"
    public let displayID: CGDirectDisplayID
    public let captureRectPoints: CGRect     // captured area in global points (events map into this)
    public let scale: CGFloat                // pixels per point
    public let cropRect: CGRect?             // AVCaptureScreenInput.cropRect (display-local points); nil = full display
}

public enum TargetResolver {
    public enum ResolveError: Error { case noDisplay, noWindow, badRegion }

    private static func scale(for displayID: CGDirectDisplayID, pointWidth: CGFloat) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), pointWidth > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / pointWidth
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// Convert a global (top-left origin) rect into AVCaptureScreenInput.cropRect, which is in the
    /// display's local coordinate space with a bottom-left origin (Quartz). Verified by Task 4.
    private static func cropRectForDisplay(_ globalRect: CGRect, displayBounds: CGRect) -> CGRect {
        let localX = globalRect.minX - displayBounds.minX
        let topLeftY = globalRect.minY - displayBounds.minY
        let bottomLeftY = displayBounds.height - (topLeftY + globalRect.height)
        return CGRect(x: localX, y: bottomLeftY, width: globalRect.width, height: globalRect.height)
    }

    public static func resolve(displayIndex: Int?, windowQuery: String?, region: CGRect?) throws -> ResolvedTarget {
        // WINDOW
        if let query = windowQuery {
            let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
            guard let bounds = WindowFinder.selectBounds(in: list, matching: query) else { throw ResolveError.noWindow }
            let did = activeDisplays().first(where: { CGDisplayBounds($0).intersects(bounds) }) ?? CGMainDisplayID()
            let dRect = CGDisplayBounds(did)
            let s = scale(for: did, pointWidth: dRect.width)
            return ResolvedTarget(kind: "window", displayID: did, captureRectPoints: bounds, scale: s,
                                  cropRect: cropRectForDisplay(bounds, displayBounds: dRect))
        }

        // DISPLAY selection (index into active displays; default main)
        let displays = activeDisplays()
        let did: CGDirectDisplayID
        if let idx = displayIndex {
            guard idx >= 0, idx < displays.count else { throw ResolveError.noDisplay }
            did = displays[idx]
        } else {
            did = CGMainDisplayID()
        }
        let dRect = CGDisplayBounds(did)
        let s = scale(for: did, pointWidth: dRect.width)

        // REGION
        if let region = region {
            guard dRect.contains(region) else { throw ResolveError.badRegion }
            return ResolvedTarget(kind: "region", displayID: did, captureRectPoints: region, scale: s,
                                  cropRect: cropRectForDisplay(region, displayBounds: dRect))
        }

        // FULL DISPLAY
        return ResolvedTarget(kind: "display", displayID: did, captureRectPoints: dRect, scale: s, cropRect: nil)
    }
}
```

- [ ] **Step 3: Rewrite Recorder**

Replace the ENTIRE contents of `Sources/ShortsCastCapture/Recorder.swift` with:
```swift
// Sources/ShortsCastCapture/Recorder.swift
import Foundation
import CoreGraphics
import ShortsCastCore

public enum Recorder {
    public enum RecorderError: Error { case noFramesCaptured }
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
        let session = AVScreenCaptureSession(outputURL: tmpMov, displayID: target.displayID,
                                             cropRect: target.cropRect, pixelSize: geometry.pixelSize)
        try await session.start()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        let times = await session.stop()
        tap.stop()

        defer { try? FileManager.default.removeItem(at: tmpMov) }
        if let writerError = session.writerError { throw writerError }
        guard session.firstFramePTSSeconds != nil else { throw RecorderError.noFramesCaptured }

        let log = builder.build(firstFrameT: times.firstFrameT, endT: times.endT)
        let meta = BundleMeta(targetKind: target.kind, displayID: target.displayID,
                              scale: Double(target.scale), captureRect: target.captureRectPoints,
                              appVersion: appVersion, created: createdISO)
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: tmpMov, to: outBundle)
        return Result(bundleURL: outBundle, eventLog: log)
    }
}
```

- [ ] **Step 4: Delete the SCK session and fix the CLI await**

```bash
git rm Sources/ShortsCastCapture/ScreenCaptureSession.swift
```
In `Sources/shortscast-rec/main.swift`, find:
```swift
        let target = try await TargetResolver.resolve(
            displayIndex: options.displayIndex,
            windowQuery: options.windowQuery,
            region: options.region)
```
and remove the `await` (resolve is now synchronous):
```swift
        let target = try TargetResolver.resolve(
            displayIndex: options.displayIndex,
            windowQuery: options.windowQuery,
            region: options.region)
```
(Leave the `#available` guards in main.swift for now; they are removed in Task 3.)

- [ ] **Step 5: Build and run the suite**

Run: `swift build` then `swift test`
Expected: builds with no errors; the full suite passes (the pure capture tests are unchanged; no new tests in this task). Confirm `git ls-files | grep ScreenCaptureSession` returns nothing.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortsCastCapture/AVScreenCaptureSession.swift Sources/ShortsCastCapture/TargetResolver.swift Sources/ShortsCastCapture/Recorder.swift Sources/shortscast-rec/main.swift
git commit -m "feat: swap capture backend to AVFoundation AVCaptureScreenInput"
```

---

### Task 3: Remove the now-dead macOS 12.3 guards

**Files:**
- Modify: `Sources/ShortsCastEditor/EditorModel.swift` (drop `@available(macOS 12.3, *)` on `record`)
- Modify: `Sources/shortscast-rec/main.swift` (remove both `#available(macOS 12.3, *)` guards)

**Interfaces:**
- No API change beyond removing availability attributes. `EditorModel.record` and the CLI are now unconditional on macOS 12.

- [ ] **Step 1: EditorModel**

In `Sources/ShortsCastEditor/EditorModel.swift`, find:
```swift
    @available(macOS 12.3, *)
    public func record(target: ResolvedTarget, seconds: Double, outBundle: URL,
```
and delete the `@available(macOS 12.3, *)` line so the method is unconditional:
```swift
    public func record(target: ResolvedTarget, seconds: Double, outBundle: URL,
```

- [ ] **Step 2: CLI main**

In `Sources/shortscast-rec/main.swift`, remove the top-level guard block:
```swift
guard #available(macOS 12.3, *) else {
    fail("shortscast-rec requires macOS 12.3 or later (ScreenCaptureKit).")
}
```
and the in-`Task` guard line:
```swift
    // The top-level #available guard does not propagate into this async closure.
    guard #available(macOS 12.3, *) else { exit(1) }
```
Leave the rest of `main.swift` (parse, permissions, the `Task { … }` + `CFRunLoopRun()`) intact.

- [ ] **Step 3: Build and run the suite**

Run: `swift build` then `swift test`
Expected: builds; full suite (114 + WindowFinder's 4 = 118) passes. No availability warnings about `Recorder`/`ResolvedTarget`.

- [ ] **Step 4: Commit**

```bash
git add Sources/ShortsCastEditor/EditorModel.swift Sources/shortscast-rec/main.swift
git commit -m "chore: drop macOS 12.3 availability guards (AVFoundation capture is 10.7+)"
```

---

### Task 4: Manual capture verification (the payoff)

**Files:** none (verification + a short results note).

This task is run by a human on this Mac; it verifies live capture now works.

- [ ] **Step 1: Build the release CLI**

Run: `swift build -c release`
Expected: succeeds; `.build/release/shortscast-rec` exists.

- [ ] **Step 2: Grant permission once**

Run: `.build/release/shortscast-rec --seconds 5 --out /tmp/cap.shortscast --direct`
If it reports missing Accessibility (the event tap needs it), grant the hosting app Accessibility in System Settings and re-run. (Screen Recording for `AVCaptureScreenInput` should already be granted from the spike.)

- [ ] **Step 3: Full-display capture**

During the 5 seconds, click around and type. Expected stdout:
- `Wrote /tmp/cap.shortscast`
- a non-zero `Events:` count
- `Director: N segments, M keyframes` with N ≥ 1.

Then `open /tmp/cap.shortscast/raw.mov` — confirm it plays and shows your screen (no baked cursor). Spot-check `events.json`: click points within the display's pixel bounds, t within `[0, duration]`.

- [ ] **Step 4: Region capture**

Run: `.build/release/shortscast-rec --seconds 4 --out /tmp/region.shortscast --rect 0,0,640,480 --direct`
Confirm `raw.mov` shows the top-left 640×480 region (×backing scale) and clicks inside it appear in `events.json`. **If the captured region is vertically offset/flipped, the `cropRectForDisplay` y-conversion needs adjusting — fix it in `TargetResolver` and re-run.**

- [ ] **Step 5: Window capture**

Run: `.build/release/shortscast-rec --seconds 4 --out /tmp/win.shortscast --window <an-open-app-name> --direct`
Confirm the chosen window's region is captured.

- [ ] **Step 6: End-to-end through export**

Export the captured bundle: `.build/release/shortscast-export /tmp/cap.shortscast --format 9:16,1:1 --out /tmp/cap-exports` → confirm MP4s with the auto-zoom following your real clicks, framed on the styled background.

- [ ] **Step 7: Record results**

Append a short pass/fail note per step to the report file. If a code fix was needed (e.g. the region y-flip), commit it and re-run the affected step.

---

## Self-Review

**Spec coverage:**
- `WindowFinder` (pure, tested) → Task 1.
- `AVScreenCaptureSession` (AVCaptureScreenInput→VideoDataOutput→AVAssetWriter, host-clock PTS, capturesCursor=false) → Task 2 Step 1.
- `TargetResolver` rewrite (CoreGraphics; display/region/window; `ResolvedTarget` reshaped) → Task 2 Steps 2.
- `Recorder` swap to `AVScreenCaptureSession` → Task 2 Step 3. Delete `ScreenCaptureSession` → Task 2 Step 4.
- Remove all `@available(macOS 12.3)` guards (capture via the rewrites; `EditorModel.record` + CLI) → Tasks 2 (capture) and 3 (editor + CLI).
- Manual capture verification (display/region/window + export) → Task 4.
- Unchanged pure suite still passing → asserted in Tasks 2-3.

**Placeholder scan:** No TBD/TODO; complete Swift in every code step. The cropRect y-convention is the one explicitly-flagged verify-during-run item (Task 4 Step 4), with the concrete fix location named.

**Type consistency:** `WindowFinder.selectBounds(in:matching:)` matches between Tasks 1 and 2. `ResolvedTarget { kind, displayID: CGDirectDisplayID, captureRectPoints, scale, cropRect }` produced in Task 2's resolver and consumed by Task 2's `Recorder` (and `EditorModel.record` in Task 3, which only passes it through). `AVScreenCaptureSession(outputURL:displayID:cropRect:pixelSize:)` + `start()`/`stop()`/`firstFramePTSSeconds`/`writerError` match between Task 2 Step 1 and Step 3. `BundleMeta(... displayID: UInt32?)` accepts the `CGDirectDisplayID` (UInt32) via optional promotion. `machNowSeconds()`/`CaptureGeometry`/`EventLogBuilder`/`ProjectBundle` reused with their existing signatures.

## Notes

- After this plan, capture works on macOS 12.6; the only thing still requiring a newer OS would be a future ScreenCaptureKit path (not needed).
- Plan 5's `RecordSheet` no longer needs an availability gate (capture is unconditional); update that when Plan 5 is built/executed.
