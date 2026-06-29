# ShortsCast Compositor & Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `ShortsCastRender` (a render/compositor library) and `shortscast-export` (a CLI) that read a `.shortscast` bundle, run the `Director`, composite each frame (auto-zoom crop, styled background, rounded+shadowed framing, synthetic cursor + click ripples) with Core Image, and export an H.264 MP4 per `OutputFormat`.

**Architecture:** Pure logic (`RenderStyle`, `FrameLayout`, `CursorRenderer`) is unit-tested; the Core Image `FrameCompositor` is verified by rendering frames to bitmaps and asserting sentinel pixels; the AVFoundation `VideoExporter`/`ExportJob` are verified with a synthetic test video. No ScreenCaptureKit dependency, so the whole plan builds and verifies on macOS 12.6.

**Tech Stack:** Swift 5.7 (Xcode 14.2), SwiftPM, XCTest, Core Image, AVFoundation, CoreVideo, CoreMedia, CoreGraphics.

## Global Constraints

- Swift tools `5.7`; package platform floor `.macOS(.v12)`.
- `ShortsCastRender` depends on `ShortsCastCore` and `ShortsCastCapture`; no ScreenCaptureKit.
- Source frames and `Director.cropRect(...)` are in source **pixel space, top-left origin**; `EventLog.screenSize` is that pixel size. Core Image works in **bottom-left origin**, so crop rects and cursor points are Y-flipped using `screenSize.height` when mapping into CI space.
- `cropRect` already has the output format's aspect ratio; `OutputFormat.exportSize` has the same aspect; the crop→content scale is uniform (no distortion).
- Output: H.264 `.mp4` at `format.exportSize`, one pass per format, source presentation timestamps preserved.
- v1 backgrounds: solid + linear gradient only (no wallpaper image). Cursor glyph: filled circle. One global `RenderStyle` per export.
- Colors are carried as a Codable `RGBA` (0...1 doubles), converted to `CIColor` at render time.
- Reused core/capture APIs (verbatim): `ProjectBundle.read(_) -> (eventLog: EventLog, meta: BundleMeta, rawVideoURL: URL)`; `Director(settings:).direct(log:overrides:) -> DirectorResult`; `Director.cropRect(_ result:, at: Seconds, format: OutputFormat, screen: CGSize) -> CGRect`; `DirectorResult { segments, cameraPath, cursor }`; `CursorTrack { samples: [TimedPoint], clicks: [ClickRipple] }`; `TimedPoint { t: Seconds, p: CGPoint }`; `ClickRipple { t: Seconds, point: CGPoint }`; `OutputFormat { name, aspect, exportSize, aspectRatio, static all }` with names `9:16`/`1:1`/`4:5`/`16:9`.

---

### Task 1: Package targets, scaffold, and Plan 2 cursor tweak

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ShortsCastRender/ShortsCastRender.swift`
- Create: `Sources/shortscast-export/main.swift`
- Modify: `Sources/ShortsCastCapture/TargetResolver.swift` (add `c.showsCursor = false`)
- Test: `Tests/ShortsCastRenderTests/ScaffoldTests.swift`

**Interfaces:**
- Consumes: `ShortsCastCore`, `ShortsCastCapture`.
- Produces: library product `ShortsCastRender`, executable `shortscast-export`, test target `ShortsCastRenderTests`; marker `ShortsCastRender.version: String`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/ScaffoldTests.swift
import XCTest
@testable import ShortsCastRender

final class ScaffoldTests: XCTestCase {
    func test_version_isNonEmpty() {
        XCTAssertFalse(ShortsCastRender.version.isEmpty)
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
        .library(name: "ShortsCastRender", targets: ["ShortsCastRender"]),
        .executable(name: "shortscast-rec", targets: ["shortscast-rec"]),
        .executable(name: "shortscast-export", targets: ["shortscast-export"])
    ],
    targets: [
        .target(name: "ShortsCastCore"),
        .testTarget(name: "ShortsCastCoreTests", dependencies: ["ShortsCastCore"]),
        .target(name: "ShortsCastCapture", dependencies: ["ShortsCastCore"]),
        .testTarget(name: "ShortsCastCaptureTests", dependencies: ["ShortsCastCapture"]),
        .target(name: "ShortsCastRender", dependencies: ["ShortsCastCore", "ShortsCastCapture"]),
        .testTarget(name: "ShortsCastRenderTests", dependencies: ["ShortsCastRender"]),
        .executableTarget(name: "shortscast-rec", dependencies: ["ShortsCastCapture", "ShortsCastCore"]),
        .executableTarget(name: "shortscast-export", dependencies: ["ShortsCastRender", "ShortsCastCore", "ShortsCastCapture"])
    ]
)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ScaffoldTests`
Expected: FAIL — `ShortsCastRender` module does not exist.

- [ ] **Step 4: Create marker, CLI stub, and apply the capture tweak**

```swift
// Sources/ShortsCastRender/ShortsCastRender.swift
import Foundation

public enum ShortsCastRender {
    public static let version = "0.1.0"
}
```

```swift
// Sources/shortscast-export/main.swift
import Foundation
import ShortsCastRender

// Fleshed out in Task 9. Stub keeps the executable target compiling.
FileHandle.standardError.write(Data("shortscast-export \(ShortsCastRender.version)\n".utf8))
```

In `Sources/ShortsCastCapture/TargetResolver.swift`, find the `config(pixelWidth:pixelHeight:)` helper. After the line `c.queueDepth = 6`, add:

```swift
        c.showsCursor = false // the compositor draws a synthetic cursor; don't bake the OS cursor into raw.mov
```

- [ ] **Step 5: Run test + build to verify**

Run: `swift test --filter ScaffoldTests` then `swift build`
Expected: scaffold test PASSES; `swift build` succeeds and produces `shortscast-export`. Run `swift test` to confirm the full prior suite (72) plus the new scaffold test still pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ShortsCastRender Sources/shortscast-export Tests/ShortsCastRenderTests Sources/ShortsCastCapture/TargetResolver.swift
git commit -m "feat: scaffold ShortsCastRender + shortscast-export; disable baked cursor in capture"
```

---

### Task 2: RGBA + RenderStyle

**Files:**
- Create: `Sources/ShortsCastRender/RenderStyle.swift`
- Test: `Tests/ShortsCastRenderTests/RenderStyleTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct RGBA: Codable, Equatable { var r, g, b, a: Double; init(_ r:_ g:_ b:_ a:); var ciColor: CIColor }`
  - `struct RenderStyle: Codable, Equatable` with nested `enum Background: Codable, Equatable { case solid(RGBA); case gradient(top: RGBA, bottom: RGBA) }` and fields `background, cornerRadius: CGFloat, shadowOpacity: Double, shadowBlur: CGFloat, shadowOffsetY: CGFloat, paddingFraction: CGFloat, cursorRadius: CGFloat, cursorColor: RGBA, rippleDuration: Double, rippleMaxRadius: CGFloat`; plus `static let \`default\`: RenderStyle`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/RenderStyleTests.swift
import XCTest
import CoreImage
@testable import ShortsCastRender

final class RenderStyleTests: XCTestCase {
    func test_default_hasSaneValues() {
        let s = RenderStyle.default
        XCTAssertGreaterThan(s.paddingFraction, 0)
        XCTAssertLessThan(s.paddingFraction, 0.49)
        XCTAssertGreaterThan(s.cornerRadius, 0)
        XCTAssertGreaterThan(s.rippleDuration, 0)
    }
    func test_jsonRoundTrip_preservesStyleAndBackgroundCase() throws {
        let s = RenderStyle(
            background: .gradient(top: RGBA(0.1, 0.2, 0.3, 1), bottom: RGBA(0, 0, 0, 1)),
            cornerRadius: 20, shadowOpacity: 0.4, shadowBlur: 18, shadowOffsetY: 10,
            paddingFraction: 0.05, cursorRadius: 16, cursorColor: RGBA(1, 1, 1, 1),
            rippleDuration: 0.5, rippleMaxRadius: 40)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(RenderStyle.self, from: data)
        XCTAssertEqual(decoded, s)
    }
    func test_rgba_toCIColorComponents() {
        let c = RGBA(0.25, 0.5, 0.75, 1).ciColor
        XCTAssertEqual(Double(c.red), 0.25, accuracy: 1e-6)
        XCTAssertEqual(Double(c.green), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(c.blue), 0.75, accuracy: 1e-6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RenderStyleTests`
Expected: FAIL — `RenderStyle` / `RGBA` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastRender/RenderStyle.swift
import Foundation
import CoreGraphics
import CoreImage

public struct RGBA: Codable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var ciColor: CIColor {
        CIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

public struct RenderStyle: Codable, Equatable {
    public enum Background: Codable, Equatable {
        case solid(RGBA)
        case gradient(top: RGBA, bottom: RGBA)
    }
    public var background: Background
    public var cornerRadius: CGFloat
    public var shadowOpacity: Double
    public var shadowBlur: CGFloat
    public var shadowOffsetY: CGFloat
    public var paddingFraction: CGFloat
    public var cursorRadius: CGFloat
    public var cursorColor: RGBA
    public var rippleDuration: Double
    public var rippleMaxRadius: CGFloat

    public init(background: Background, cornerRadius: CGFloat, shadowOpacity: Double,
                shadowBlur: CGFloat, shadowOffsetY: CGFloat, paddingFraction: CGFloat,
                cursorRadius: CGFloat, cursorColor: RGBA, rippleDuration: Double,
                rippleMaxRadius: CGFloat) {
        self.background = background; self.cornerRadius = cornerRadius
        self.shadowOpacity = shadowOpacity; self.shadowBlur = shadowBlur
        self.shadowOffsetY = shadowOffsetY; self.paddingFraction = paddingFraction
        self.cursorRadius = cursorRadius; self.cursorColor = cursorColor
        self.rippleDuration = rippleDuration; self.rippleMaxRadius = rippleMaxRadius
    }

    public static let `default` = RenderStyle(
        background: .gradient(top: RGBA(0.16, 0.18, 0.30, 1), bottom: RGBA(0.05, 0.06, 0.12, 1)),
        cornerRadius: 28, shadowOpacity: 0.5, shadowBlur: 30, shadowOffsetY: 14,
        paddingFraction: 0.06, cursorRadius: 18, cursorColor: RGBA(1, 1, 1, 1),
        rippleDuration: 0.5, rippleMaxRadius: 60)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RenderStyleTests`
Expected: PASS — all three cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastRender/RenderStyle.swift Tests/ShortsCastRenderTests/RenderStyleTests.swift
git commit -m "feat: add RenderStyle and RGBA color config"
```

---

### Task 3: FrameLayout (content rect geometry)

**Files:**
- Create: `Sources/ShortsCastRender/FrameLayout.swift`
- Test: `Tests/ShortsCastRenderTests/FrameLayoutTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum FrameLayout { static func contentRect(exportSize: CGSize, paddingFraction: CGFloat) -> CGRect }` — aspect-preserving, centered inset; `paddingFraction` clamped to `[0, 0.49]`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/FrameLayoutTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastRender

final class FrameLayoutTests: XCTestCase {
    func test_contentRect_centeredInset() {
        let r = FrameLayout.contentRect(exportSize: CGSize(width: 1080, height: 1920), paddingFraction: 0.05)
        XCTAssertEqual(r.width, 1080 * 0.9, accuracy: 1e-6)   // 972
        XCTAssertEqual(r.height, 1920 * 0.9, accuracy: 1e-6)  // 1728
        XCTAssertEqual(r.midX, 540, accuracy: 1e-6)
        XCTAssertEqual(r.midY, 960, accuracy: 1e-6)
    }
    func test_contentRect_zeroPaddingIsFullFrame() {
        let r = FrameLayout.contentRect(exportSize: CGSize(width: 800, height: 800), paddingFraction: 0)
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 800, height: 800))
    }
    func test_contentRect_clampsExcessivePadding() {
        let r = FrameLayout.contentRect(exportSize: CGSize(width: 1000, height: 1000), paddingFraction: 0.9)
        // clamped to 0.49 -> scale 0.02 -> 20x20, still centered and positive
        XCTAssertGreaterThan(r.width, 0)
        XCTAssertEqual(r.midX, 500, accuracy: 1e-6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FrameLayoutTests`
Expected: FAIL — `FrameLayout` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastRender/FrameLayout.swift
import Foundation
import CoreGraphics

public enum FrameLayout {
    /// The centered, aspect-preserving rect the screen content occupies inside the export frame.
    public static func contentRect(exportSize: CGSize, paddingFraction: CGFloat) -> CGRect {
        let p = min(max(paddingFraction, 0), 0.49)
        let scale = 1 - 2 * p
        let w = exportSize.width * scale
        let h = exportSize.height * scale
        return CGRect(x: (exportSize.width - w) / 2, y: (exportSize.height - h) / 2, width: w, height: h)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FrameLayoutTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastRender/FrameLayout.swift Tests/ShortsCastRenderTests/FrameLayoutTests.swift
git commit -m "feat: add FrameLayout content-rect geometry"
```

---

### Task 4: CursorRenderer (position + ripple selection)

**Files:**
- Create: `Sources/ShortsCastRender/CursorRenderer.swift`
- Test: `Tests/ShortsCastRenderTests/CursorRendererTests.swift`

**Interfaces:**
- Consumes: `TimedPoint`, `ClickRipple`, `Seconds` (core).
- Produces:
  - `struct RippleState: Equatable { var point: CGPoint; var progress: Double }`
  - `enum CursorRenderer { static func position(at t: Seconds, samples: [TimedPoint]) -> CGPoint?; static func activeRipples(at t: Seconds, clicks: [ClickRipple], duration: Double) -> [RippleState] }`
  - `position`: nil if empty; clamps before first / after last; linear interpolation between bracketing samples. `activeRipples`: ripples with `0 <= t - click.t <= duration` (duration > 0), `progress = (t - click.t) / duration`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/CursorRendererTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastRender

final class CursorRendererTests: XCTestCase {
    func test_position_nilWhenEmpty() {
        XCTAssertNil(CursorRenderer.position(at: 1, samples: []))
    }
    func test_position_clampsAndInterpolates() {
        let s = [TimedPoint(t: 0, p: CGPoint(x: 0, y: 0)),
                 TimedPoint(t: 2, p: CGPoint(x: 100, y: 0))]
        XCTAssertEqual(CursorRenderer.position(at: -1, samples: s), CGPoint(x: 0, y: 0))   // clamp start
        XCTAssertEqual(CursorRenderer.position(at: 9, samples: s), CGPoint(x: 100, y: 0))  // clamp end
        let mid = CursorRenderer.position(at: 1, samples: s)!
        XCTAssertEqual(mid.x, 50, accuracy: 1e-6)                                          // linear midpoint
    }
    func test_activeRipples_windowAndProgress() {
        let clicks = [ClickRipple(t: 1.0, point: CGPoint(x: 10, y: 10)),
                      ClickRipple(t: 5.0, point: CGPoint(x: 20, y: 20))]
        let active = CursorRenderer.activeRipples(at: 1.25, clicks: clicks, duration: 0.5)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].point, CGPoint(x: 10, y: 10))
        XCTAssertEqual(active[0].progress, 0.5, accuracy: 1e-6) // (1.25-1.0)/0.5
    }
    func test_activeRipples_excludesOutOfWindow() {
        let clicks = [ClickRipple(t: 1.0, point: .zero)]
        XCTAssertTrue(CursorRenderer.activeRipples(at: 2.0, clicks: clicks, duration: 0.5).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CursorRendererTests`
Expected: FAIL — `CursorRenderer` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastRender/CursorRenderer.swift
import Foundation
import CoreGraphics
import ShortsCastCore

public struct RippleState: Equatable {
    public var point: CGPoint
    public var progress: Double
    public init(point: CGPoint, progress: Double) { self.point = point; self.progress = progress }
}

public enum CursorRenderer {
    /// Interpolated cursor position (source pixel space) at time t; nil if no samples.
    public static func position(at t: Seconds, samples: [TimedPoint]) -> CGPoint? {
        guard let first = samples.first else { return nil }
        if t <= first.t { return first.p }
        guard let last = samples.last, t < last.t else { return samples.last?.p }
        for i in 1..<samples.count where samples[i].t >= t {
            let a = samples[i - 1], b = samples[i]
            let span = b.t - a.t
            let u = span > 0 ? (t - a.t) / span : 0
            return CGPoint(x: a.p.x + (b.p.x - a.p.x) * CGFloat(u),
                           y: a.p.y + (b.p.y - a.p.y) * CGFloat(u))
        }
        return last.p
    }

    /// Ripples currently animating at time t, with progress in [0,1].
    public static func activeRipples(at t: Seconds, clicks: [ClickRipple], duration: Double) -> [RippleState] {
        guard duration > 0 else { return [] }
        return clicks.compactMap { c in
            let dt = t - c.t
            guard dt >= 0, dt <= duration else { return nil }
            return RippleState(point: c.point, progress: dt / duration)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CursorRendererTests`
Expected: PASS — all four cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastRender/CursorRenderer.swift Tests/ShortsCastRenderTests/CursorRendererTests.swift
git commit -m "feat: add CursorRenderer position and ripple selection"
```

---

### Task 5: FrameCompositor — background + framed content

**Files:**
- Create: `Sources/ShortsCastRender/FrameCompositor.swift`
- Create: `Tests/ShortsCastRenderTests/RenderTestSupport.swift`
- Test: `Tests/ShortsCastRenderTests/FrameCompositorTests.swift`

**Interfaces:**
- Consumes: `RenderStyle`/`RGBA` (Task 2), `FrameLayout` (Task 3), `OutputFormat`, `CursorTrack` (core).
- Produces:
  - `final class FrameCompositor { let style; let format; let screenSize; let context: CIContext; init(style:format:screenSize:); func composite(source: CIImage, crop: CGRect, time: Seconds, cursor: CursorTrack) -> CIImage }`
  - In THIS task `composite` renders background + framed (rounded + shadowed) content; the cursor/ripples layer is added in Task 6 (leave a `// cursor overlay added in Task 6` marker and return the background+content result).
  - `RenderTestSupport.swift` provides a test helper `func samplePixel(_ image: CIImage, at p: CGPoint, exportSize: CGSize, context: CIContext) -> RGBA` (renders the CIImage and reads one pixel, BL-origin coords).

- [ ] **Step 1: Write the test support helper**

```swift
// Tests/ShortsCastRenderTests/RenderTestSupport.swift
import CoreImage
import CoreGraphics
@testable import ShortsCastRender

/// Renders `image` to a bitmap and returns the pixel at `p` (export/CI space, bottom-left origin).
func samplePixel(_ image: CIImage, at p: CGPoint, exportSize: CGSize, context: CIContext) -> RGBA {
    let rect = CGRect(origin: .zero, size: exportSize)
    let cg = context.createCGImage(image, from: rect)!
    let cs = CGColorSpaceCreateDeviceRGB()
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw the full image shifted so that pixel p lands in the 1x1 context.
    ctx.draw(cg, in: CGRect(x: -p.x, y: -p.y, width: exportSize.width, height: exportSize.height))
    return RGBA(Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255, Double(px[3]) / 255)
}

/// A solid-color CIImage of the given size (premultiplied, opaque).
func solidImage(_ color: RGBA, size: CGSize) -> CIImage {
    CIImage(color: color.ciColor).cropped(to: CGRect(origin: .zero, size: size))
}
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/FrameCompositorTests.swift
import XCTest
import CoreImage
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastRender

final class FrameCompositorTests: XCTestCase {
    private func style(bg: RGBA) -> RenderStyle {
        RenderStyle(background: .solid(bg), cornerRadius: 0, shadowOpacity: 0, shadowBlur: 0,
                    shadowOffsetY: 0, paddingFraction: 0.1, cursorRadius: 18,
                    cursorColor: RGBA(0, 0, 1, 1), rippleDuration: 0.5, rippleMaxRadius: 60)
    }

    func test_backgroundAndContent_areComposited() {
        let screen = CGSize(width: 1000, height: 1000)
        let fmt = OutputFormat.square1x1 // 1080x1080, aspect matches a 1000x1000 crop
        let bg = RGBA(1, 0, 0, 1)        // red background
        let comp = FrameCompositor(style: style(bg: bg), format: fmt, screenSize: screen)
        let source = solidImage(RGBA(0, 1, 0, 1), size: screen) // green screen content
        let crop = CGRect(x: 0, y: 0, width: 1000, height: 1000) // full screen
        let out = comp.composite(source: source, crop: crop, time: 0, cursor: CursorTrack(samples: [], clicks: []))

        // Center is inside the content rect -> green.
        let center = samplePixel(out, at: CGPoint(x: 540, y: 540), exportSize: fmt.exportSize, context: comp.context)
        XCTAssertEqual(center.g, 1, accuracy: 0.15)
        XCTAssertLessThan(center.r, 0.3)

        // Left-edge middle is in the padding margin -> red background.
        let edge = samplePixel(out, at: CGPoint(x: 5, y: 540), exportSize: fmt.exportSize, context: comp.context)
        XCTAssertEqual(edge.r, 1, accuracy: 0.15)
        XCTAssertLessThan(edge.g, 0.3)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter FrameCompositorTests`
Expected: FAIL — `FrameCompositor` not defined.

- [ ] **Step 4: Write minimal implementation**

```swift
// Sources/ShortsCastRender/FrameCompositor.swift
import Foundation
import CoreImage
import CoreGraphics
import CoreVideo
import ShortsCastCore

public final class FrameCompositor {
    public let style: RenderStyle
    public let format: OutputFormat
    public let screenSize: CGSize
    public let context: CIContext

    let exportSize: CGSize
    let contentRect: CGRect
    private let background: CIImage
    private let roundedMask: CIImage
    private let shadow: CIImage

    public init(style: RenderStyle, format: OutputFormat, screenSize: CGSize) {
        self.style = style
        self.format = format
        self.screenSize = screenSize
        // Disable color management so rendered pixel values match configured colors (predictable tests).
        self.context = CIContext(options: [.workingColorSpace: NSNull()])
        self.exportSize = format.exportSize
        self.contentRect = FrameLayout.contentRect(exportSize: format.exportSize,
                                                    paddingFraction: style.paddingFraction)
        self.background = FrameCompositor.makeBackground(style.background, size: format.exportSize)
        self.roundedMask = FrameCompositor.makeRoundedMask(size: contentRect.size, radius: style.cornerRadius)
        self.shadow = FrameCompositor.makeShadow(maskSize: contentRect.size, radius: style.cornerRadius,
                                                 contentOrigin: contentRect.origin, style: style)
    }

    public func composite(source: CIImage, crop: CGRect, time: Seconds, cursor: CursorTrack) -> CIImage {
        // Map the top-left source crop into CI bottom-left space.
        let ciCrop = CGRect(x: crop.minX, y: screenSize.height - crop.maxY,
                            width: crop.width, height: crop.height)
        var content = source.cropped(to: ciCrop)
            .transformed(by: CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY))
        let sx = contentRect.width / crop.width
        let sy = contentRect.height / crop.height
        content = content
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: contentRect.minX, y: contentRect.minY))

        let mask = roundedMask.transformed(by: CGAffineTransform(translationX: contentRect.minX,
                                                                 y: contentRect.minY))
        let rounded = content.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": CIImage.empty(),
            "inputMaskImage": mask
        ])

        let out = rounded
            .composited(over: shadow)
            .composited(over: background)
        // cursor overlay added in Task 6
        return out.cropped(to: CGRect(origin: .zero, size: exportSize))
    }

    // MARK: - Precomputed layers

    static func makeBackground(_ bg: RenderStyle.Background, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)
        switch bg {
        case .solid(let c):
            return CIImage(color: c.ciColor).cropped(to: rect)
        case .gradient(let top, let bottom):
            let f = CIFilter(name: "CILinearGradient")!
            f.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
            f.setValue(CIVector(x: 0, y: size.height), forKey: "inputPoint1")
            f.setValue(bottom.ciColor, forKey: "inputColor0")
            f.setValue(top.ciColor, forKey: "inputColor1")
            return f.outputImage!.cropped(to: rect)
        }
    }

    /// A white rounded-rectangle alpha mask of `size`, origin (0,0).
    static func makeRoundedMask(size: CGSize, radius: CGFloat) -> CIImage {
        let w = max(1, Int(size.width.rounded())), h = max(1, Int(size.height.rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let r = max(0, min(radius, CGFloat(min(w, h)) / 2))
        let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                          cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.addPath(path); ctx.fillPath()
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// A soft drop shadow placed under the content rect.
    static func makeShadow(maskSize: CGSize, radius: CGFloat, contentOrigin: CGPoint,
                           style: RenderStyle) -> CIImage {
        let mask = makeRoundedMask(size: maskSize, radius: radius)
        let black = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(style.shadowOpacity)),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        let blurred = black.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": style.shadowBlur
        ])
        // Offset downward in screen terms => negative y in CI bottom-left space.
        return blurred.transformed(by: CGAffineTransform(translationX: contentOrigin.x,
                                                         y: contentOrigin.y - style.shadowOffsetY))
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter FrameCompositorTests`
Expected: PASS — background red at the edge, content green at the center.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortsCastRender/FrameCompositor.swift Tests/ShortsCastRenderTests/RenderTestSupport.swift Tests/ShortsCastRenderTests/FrameCompositorTests.swift
git commit -m "feat: compositor background + rounded/shadowed framed content"
```

---

### Task 6: FrameCompositor — cursor + click ripples overlay

**Files:**
- Modify: `Sources/ShortsCastRender/FrameCompositor.swift`
- Test: `Tests/ShortsCastRenderTests/FrameCompositorCursorTests.swift`

**Interfaces:**
- Consumes: `CursorRenderer`/`RippleState` (Task 4), the existing `FrameCompositor` (Task 5).
- Produces: `composite(...)` now draws a synthetic cursor (filled circle from `CursorRenderer.position`) and active click ripples (expanding/fading rings) on top of the framed content, mapped through the same crop→content transform; the cursor is omitted when its source point lies outside `crop`. Adds a private `sourceToExport(_ point: CGPoint, crop: CGRect) -> CGPoint` helper and a precomputed unit circle/ring.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/FrameCompositorCursorTests.swift
import XCTest
import CoreImage
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastRender

final class FrameCompositorCursorTests: XCTestCase {
    private func style() -> RenderStyle {
        RenderStyle(background: .solid(RGBA(1, 0, 0, 1)), cornerRadius: 0, shadowOpacity: 0,
                    shadowBlur: 0, shadowOffsetY: 0, paddingFraction: 0.0, cursorRadius: 40,
                    cursorColor: RGBA(0, 0, 1, 1), rippleDuration: 0.5, rippleMaxRadius: 80)
    }

    func test_cursor_drawnAtMappedPosition() {
        let screen = CGSize(width: 1080, height: 1080)
        let fmt = OutputFormat.square1x1 // 1080x1080
        let comp = FrameCompositor(style: style(), format: fmt, screenSize: screen)
        let source = solidImage(RGBA(0, 1, 0, 1), size: screen) // green
        // Cursor at the center of the screen (source TL coords) the whole time.
        let cursor = CursorTrack(samples: [TimedPoint(t: 0, p: CGPoint(x: 540, y: 540))], clicks: [])
        let out = comp.composite(source: source, crop: CGRect(x: 0, y: 0, width: 1080, height: 1080),
                                 time: 0, cursor: cursor)
        // With padding 0 and a full-screen crop, center maps to export center; cursor is blue there.
        let center = samplePixel(out, at: CGPoint(x: 540, y: 540), exportSize: fmt.exportSize, context: comp.context)
        XCTAssertEqual(center.b, 1, accuracy: 0.2)
        XCTAssertLessThan(center.g, 0.5) // green content covered by blue cursor
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter FrameCompositorCursorTests`
Expected: FAIL — the center is still green (cursor not yet drawn).

- [ ] **Step 3: Add the cursor/ripple overlay**

In `FrameCompositor.swift`, add a stored precomputed circle and replace the `composite(...)` return path. First add two precomputed images in `init` (after `self.shadow = ...`):

```swift
        self.cursorDot = FrameCompositor.makeFilledCircle(radius: style.cursorRadius, color: style.cursorColor)
        self.ringUnit = FrameCompositor.makeRing(radius: 100, thickness: 12, color: style.cursorColor)
```

Add the stored properties near the other `private let`s:

```swift
    private let cursorDot: CIImage
    private let ringUnit: CIImage
```

Add these helpers (alongside the other `static func`s):

```swift
    /// A filled circle CIImage centered at (radius, radius), size 2*radius square.
    static func makeFilledCircle(radius: CGFloat, color: RGBA) -> CIImage {
        let d = max(2, Int((radius * 2).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: d, height: d, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: d, height: d))
        ctx.setFillColor(CGColor(red: CGFloat(color.r), green: CGFloat(color.g),
                                 blue: CGFloat(color.b), alpha: CGFloat(color.a)))
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// A ring (stroked circle) CIImage of outer `radius`, centered, size 2*radius square.
    static func makeRing(radius: CGFloat, thickness: CGFloat, color: RGBA) -> CIImage {
        let d = max(2, Int((radius * 2).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: d, height: d, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.clear(CGRect(x: 0, y: 0, width: d, height: d))
        ctx.setStrokeColor(CGColor(red: CGFloat(color.r), green: CGFloat(color.g),
                                   blue: CGFloat(color.b), alpha: CGFloat(color.a)))
        ctx.setLineWidth(thickness)
        let inset = thickness / 2
        ctx.strokeEllipse(in: CGRect(x: inset, y: inset, width: CGFloat(d) - 2 * inset,
                                     height: CGFloat(d) - 2 * inset))
        return CIImage(cgImage: ctx.makeImage()!)
    }

    /// Maps a source-pixel (top-left) point into export CI space (bottom-left), or nil if outside the crop.
    func sourceToExport(_ point: CGPoint, crop: CGRect) -> CGPoint? {
        guard crop.contains(point) else { return nil }
        let ciY = screenSize.height - point.y                 // to source CI space
        let ciCropY = screenSize.height - crop.maxY
        let localX = (point.x - crop.minX) * (contentRect.width / crop.width)
        let localY = (ciY - ciCropY) * (contentRect.height / crop.height)
        return CGPoint(x: contentRect.minX + localX, y: contentRect.minY + localY)
    }
```

Then change `composite(...)` so that after building `out` (background+content) and before the final crop, it overlays ripples and the cursor:

```swift
        var layered = rounded.composited(over: shadow).composited(over: background)

        // Click ripples (under the cursor dot).
        for r in CursorRenderer.activeRipples(at: time, clicks: cursor.clicks, duration: style.rippleDuration) {
            guard let p = sourceToExport(r.point, crop: crop) else { continue }
            let radius = style.cursorRadius + (style.rippleMaxRadius - style.cursorRadius) * CGFloat(r.progress)
            let scale = radius / 100.0 // ringUnit was built at radius 100
            let alpha = CGFloat(1.0 - r.progress)
            let ring = ringUnit
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
                ])
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: p.x - radius, y: p.y - radius))
            layered = ring.composited(over: layered)
        }

        // Cursor dot.
        if let cp = CursorRenderer.position(at: time, samples: cursor.samples),
           let p = sourceToExport(cp, crop: crop) {
            let dot = cursorDot.transformed(by: CGAffineTransform(translationX: p.x - style.cursorRadius,
                                                                  y: p.y - style.cursorRadius))
            layered = dot.composited(over: layered)
        }

        return layered.cropped(to: CGRect(origin: .zero, size: exportSize))
```

Remove the old `let out = ... ; return out.cropped(...)` lines and the `// cursor overlay added in Task 6` marker (replaced by the block above).

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter FrameCompositorCursorTests`
Expected: PASS — center pixel is now blue (cursor). Also re-run `swift test --filter FrameCompositorTests` to confirm Task 5's test still passes (its style has no cursor at center because it provides an empty cursor track).

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastRender/FrameCompositor.swift Tests/ShortsCastRenderTests/FrameCompositorCursorTests.swift
git commit -m "feat: draw synthetic cursor and click ripples in compositor"
```

---

### Task 7: VideoExporter + TestVideoFactory

**Files:**
- Create: `Sources/ShortsCastRender/VideoExporter.swift`
- Create: `Tests/ShortsCastRenderTests/TestVideoFactory.swift`
- Test: `Tests/ShortsCastRenderTests/VideoExporterTests.swift`

**Interfaces:**
- Consumes: `FrameCompositor` (Tasks 5-6), `Director`/`DirectorResult`/`OutputFormat`/`EventLog` (core).
- Produces:
  - `enum VideoExporter { enum ExportError: Error { case noVideoTrack, noFramesRendered, writerFailed(Error?) }; static func export(rawVideoURL: URL, result: DirectorResult, format: OutputFormat, style: RenderStyle, screenSize: CGSize, to outURL: URL) throws }`
  - Synchronous: `AVAssetReader` pulls source frames (32BGRA), composites each via a `FrameCompositor`, writes H.264 MP4 at `format.exportSize` reusing source PTS. Throws `noVideoTrack` if the asset has no video track and `noFramesRendered` if zero frames were written.
  - `TestVideoFactory` (test target): `static func writeSolidColor(to url: URL, size: CGSize, seconds: Double, fps: Int, color: RGBA) throws` — writes a solid-color H.264 `.mov`.

- [ ] **Step 1: Write the TestVideoFactory helper**

```swift
// Tests/ShortsCastRenderTests/TestVideoFactory.swift
import AVFoundation
import CoreImage
import CoreVideo
import CoreGraphics
@testable import ShortsCastRender

enum TestVideoFactory {
    /// Writes a solid-color H.264 .mov of the given size/duration/fps.
    static func writeSolidColor(to url: URL, size: CGSize, seconds: Double, fps: Int, color: RGBA) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let ciContext = CIContext(options: [.workingColorSpace: NSNull()])
        let image = CIImage(color: color.ciColor).cropped(to: CGRect(origin: .zero, size: size))
        let total = Int(seconds * Double(fps))
        for i in 0..<total {
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            ciContext.render(image, to: pb!)
            let pts = CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps))
            adaptor.append(pb!, withPresentationTime: pts)
        }
        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
    }
}
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/VideoExporterTests.swift
import XCTest
import AVFoundation
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastRender

final class VideoExporterTests: XCTestCase {
    func test_export_producesMP4WithFormatDimensions() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vexp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let screen = CGSize(width: 1280, height: 720)
        let raw = tmp.appendingPathComponent("raw.mov")
        try TestVideoFactory.writeSolidColor(to: raw, size: screen, seconds: 1.0, fps: 30,
                                             color: RGBA(0, 1, 0, 1))

        let log = EventLog(duration: 1.0, screenSize: screen, events: [
            .click(t: 0.5, point: CGPoint(x: 640, y: 360), button: .left)
        ])
        let result = Director(settings: AutoDirectorSettings()).direct(log: log, overrides: [])

        let out = tmp.appendingPathComponent("out.mp4")
        try VideoExporter.export(rawVideoURL: raw, result: result, format: .vertical9x16,
                                 style: .default, screenSize: screen, to: out)

        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        let track = AVAsset(url: out).tracks(withMediaType: .video).first!
        XCTAssertEqual(track.naturalSize.width, 1080, accuracy: 1)
        XCTAssertEqual(track.naturalSize.height, 1920, accuracy: 1)
        XCTAssertGreaterThan(CMTimeGetSeconds(AVAsset(url: out).duration), 0.5)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter VideoExporterTests`
Expected: FAIL — `VideoExporter` not defined.

- [ ] **Step 4: Write minimal implementation**

```swift
// Sources/ShortsCastRender/VideoExporter.swift
import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreMedia
import CoreGraphics
import ShortsCastCore

public enum VideoExporter {
    public enum ExportError: Error { case noVideoTrack, noFramesRendered, writerFailed(Error?) }

    public static func export(rawVideoURL: URL, result: DirectorResult, format: OutputFormat,
                              style: RenderStyle, screenSize: CGSize, to outURL: URL) throws {
        let asset = AVAsset(url: rawVideoURL)
        guard let track = asset.tracks(withMediaType: .video).first else { throw ExportError.noVideoTrack }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        reader.add(readerOutput)

        try? FileManager.default.removeItem(at: outURL)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(format.exportSize.width),
            AVVideoHeightKey: Int(format.exportSize.height)
        ])
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput,
                                                           sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(format.exportSize.width),
            kCVPixelBufferHeightKey as String: Int(format.exportSize.height)
        ])
        writer.add(writerInput)

        let compositor = FrameCompositor(style: style, format: format, screenSize: screenSize)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var rendered = 0
        while let sample = readerOutput.copyNextSampleBuffer() {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let t = CMTimeGetSeconds(pts)
            let crop = Director(settings: AutoDirectorSettings())
                .cropRect(result, at: t, format: format, screen: screenSize)
            let ciSource = CIImage(cvPixelBuffer: imageBuffer)
            let composedImage = compositor.composite(source: ciSource, crop: crop, time: t,
                                                      cursor: result.cursor)

            while !writerInput.isReadyForMoreMediaData { usleep(1000) }
            var outBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &outBuffer)
            guard let pb = outBuffer else { continue }
            compositor.context.render(composedImage, to: pb)
            adaptor.append(pb, withPresentationTime: pts)
            rendered += 1
        }

        writerInput.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()

        if writer.status == .failed { throw ExportError.writerFailed(writer.error) }
        if rendered == 0 { throw ExportError.noFramesRendered }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter VideoExporterTests`
Expected: PASS — 1080×1920 MP4 produced from a 1280×720 source. (May take a few seconds.)

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortsCastRender/VideoExporter.swift Tests/ShortsCastRenderTests/TestVideoFactory.swift Tests/ShortsCastRenderTests/VideoExporterTests.swift
git commit -m "feat: add AVFoundation VideoExporter with synthetic-video test"
```

---

### Task 8: ExportJob facade

**Files:**
- Create: `Sources/ShortsCastRender/ExportJob.swift`
- Test: `Tests/ShortsCastRenderTests/ExportJobTests.swift`

**Interfaces:**
- Consumes: `VideoExporter` (Task 7), `ProjectBundle` (capture), `Director`/`OutputFormat` (core).
- Produces:
  - `enum ExportJob { static func run(bundleURL: URL, formats: [OutputFormat], style: RenderStyle, settings: AutoDirectorSettings, outDir: URL) throws -> [URL] }`
  - Reads the bundle, runs `Director`, exports each format to `<outDir>/<bundleBaseName>-<sanitizedFormatName>.mp4` (the `:` in a format name replaced with `x`), returns the written URLs. Creates `outDir` if missing.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/ExportJobTests.swift
import XCTest
import AVFoundation
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastRender

final class ExportJobTests: XCTestCase {
    func test_run_exportsOneMP4PerFormat() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ejob-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Build a synthetic .shortscast bundle.
        let screen = CGSize(width: 1280, height: 720)
        let raw = tmp.appendingPathComponent("src.mov")
        try TestVideoFactory.writeSolidColor(to: raw, size: screen, seconds: 1.0, fps: 30,
                                             color: RGBA(0, 0.5, 1, 1))
        let log = EventLog(duration: 1.0, screenSize: screen,
                           events: [.click(t: 0.4, point: CGPoint(x: 600, y: 300), button: .left)])
        let meta = BundleMeta(targetKind: "display", displayID: 1, scale: 1,
                              captureRect: CGRect(origin: .zero, size: screen),
                              appVersion: "test", created: "2026-06-30T00:00:00Z")
        let bundle = tmp.appendingPathComponent("clip.shortscast")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: raw, to: bundle)

        let outDir = tmp.appendingPathComponent("out")
        let urls = try ExportJob.run(bundleURL: bundle,
                                     formats: [.vertical9x16, .square1x1],
                                     style: .default, settings: AutoDirectorSettings(), outDir: outDir)

        XCTAssertEqual(urls.count, 2)
        for u in urls { XCTAssertTrue(FileManager.default.fileExists(atPath: u.path)) }
        let v = AVAsset(url: urls[0]).tracks(withMediaType: .video).first!
        XCTAssertEqual(v.naturalSize.width, 1080, accuracy: 1)
        XCTAssertEqual(v.naturalSize.height, 1920, accuracy: 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExportJobTests`
Expected: FAIL — `ExportJob` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastRender/ExportJob.swift
import Foundation
import ShortsCastCore
import ShortsCastCapture

public enum ExportJob {
    public static func run(bundleURL: URL, formats: [OutputFormat], style: RenderStyle,
                           settings: AutoDirectorSettings, outDir: URL) throws -> [URL] {
        let (eventLog, _, rawVideoURL) = try ProjectBundle.read(bundleURL)
        let result = Director(settings: settings).direct(log: eventLog, overrides: [])
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let base = bundleURL.deletingPathExtension().lastPathComponent
        var written: [URL] = []
        for format in formats {
            let safe = format.name.replacingOccurrences(of: ":", with: "x")
            let outURL = outDir.appendingPathComponent("\(base)-\(safe).mp4")
            try VideoExporter.export(rawVideoURL: rawVideoURL, result: result, format: format,
                                     style: style, screenSize: eventLog.screenSize, to: outURL)
            written.append(outURL)
        }
        return written
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ExportJobTests`
Expected: PASS — two MP4s written, 9:16 is 1080×1920.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastRender/ExportJob.swift Tests/ShortsCastRenderTests/ExportJobTests.swift
git commit -m "feat: add ExportJob facade (bundle -> MP4 per format)"
```

---

### Task 9: CLI option parsing + shortscast-export main

**Files:**
- Create: `Sources/ShortsCastRender/ExportOptions.swift`
- Modify: `Sources/shortscast-export/main.swift`
- Test: `Tests/ShortsCastRenderTests/ExportOptionsTests.swift`

**Interfaces:**
- Consumes: `OutputFormat` (core).
- Produces:
  - `struct ExportOptions: Equatable { var bundle: String; var formats: [String]; var out: String; var stylePath: String? }`
  - `enum ExportParseError: Error, Equatable { case missingRequired(String); case badValue(String); case unknownFormat(String) }`
  - `extension ExportOptions { static func parse(_ args: [String]) throws -> ExportOptions; static func resolveFormats(_ names: [String]) throws -> [OutputFormat] }`
  - `parse`: `--format a,b` (required, comma-split, non-empty), `--out <dir>` (required), positional first non-flag arg = bundle path (required), `--style <path>` (optional). `resolveFormats` maps names to `OutputFormat.all` by `name`, throwing `unknownFormat` for any miss.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastRenderTests/ExportOptionsTests.swift
import XCTest
import ShortsCastCore
@testable import ShortsCastRender

final class ExportOptionsTests: XCTestCase {
    func test_parse_minimal() throws {
        let o = try ExportOptions.parse(["clip.shortscast", "--format", "9:16,1:1", "--out", "dir"])
        XCTAssertEqual(o.bundle, "clip.shortscast")
        XCTAssertEqual(o.formats, ["9:16", "1:1"])
        XCTAssertEqual(o.out, "dir")
        XCTAssertNil(o.stylePath)
    }
    func test_parse_missingOut_throws() {
        XCTAssertThrowsError(try ExportOptions.parse(["clip", "--format", "9:16"])) { err in
            XCTAssertEqual(err as? ExportParseError, .missingRequired("--out"))
        }
    }
    func test_parse_missingBundle_throws() {
        XCTAssertThrowsError(try ExportOptions.parse(["--format", "9:16", "--out", "d"])) { err in
            XCTAssertEqual(err as? ExportParseError, .missingRequired("bundle"))
        }
    }
    func test_resolveFormats_mapsNames() throws {
        let fmts = try ExportOptions.resolveFormats(["9:16", "16:9"])
        XCTAssertEqual(fmts.map { $0.name }, ["9:16", "16:9"])
    }
    func test_resolveFormats_unknownThrows() {
        XCTAssertThrowsError(try ExportOptions.resolveFormats(["9:16", "bogus"])) { err in
            XCTAssertEqual(err as? ExportParseError, .unknownFormat("bogus"))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExportOptionsTests`
Expected: FAIL — `ExportOptions` not defined.

- [ ] **Step 3: Write the parser**

```swift
// Sources/ShortsCastRender/ExportOptions.swift
import Foundation
import ShortsCastCore

public enum ExportParseError: Error, Equatable {
    case missingRequired(String)
    case badValue(String)
    case unknownFormat(String)
}

public struct ExportOptions: Equatable {
    public var bundle: String
    public var formats: [String]
    public var out: String
    public var stylePath: String?

    public static func parse(_ args: [String]) throws -> ExportOptions {
        var bundle: String?
        var formats: [String]?
        var out: String?
        var stylePath: String?

        var i = 0
        func nextValue(_ flag: String) throws -> String {
            i += 1
            guard i < args.count else { throw ExportParseError.badValue(flag) }
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "--format":
                let parts = try nextValue(a).split(separator: ",").map(String.init)
                guard !parts.isEmpty else { throw ExportParseError.badValue(a) }
                formats = parts
            case "--out":
                out = try nextValue(a)
            case "--style":
                stylePath = try nextValue(a)
            default:
                if a.hasPrefix("--") { throw ExportParseError.badValue(a) }
                if bundle == nil { bundle = a } else { throw ExportParseError.badValue(a) }
            }
            i += 1
        }

        guard let b = bundle else { throw ExportParseError.missingRequired("bundle") }
        guard let f = formats else { throw ExportParseError.missingRequired("--format") }
        guard let o = out else { throw ExportParseError.missingRequired("--out") }
        return ExportOptions(bundle: b, formats: f, out: o, stylePath: stylePath)
    }

    public static func resolveFormats(_ names: [String]) throws -> [OutputFormat] {
        try names.map { name in
            guard let f = OutputFormat.all.first(where: { $0.name == name }) else {
                throw ExportParseError.unknownFormat(name)
            }
            return f
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ExportOptionsTests`
Expected: PASS — all five cases.

- [ ] **Step 5: Write the executable main**

```swift
// Sources/shortscast-export/main.swift
import Foundation
import ShortsCastRender
import ShortsCastCore

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let options: ExportOptions
do {
    options = try ExportOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("""
    Usage: shortscast-export <bundle.shortscast> --format 9:16[,1:1,4:5,16:9] --out <dir> [--style <style.json>]
    Error: \(error)
    """)
}

let formats: [OutputFormat]
do {
    formats = try ExportOptions.resolveFormats(options.formats)
} catch {
    fail("Invalid --format: \(error). Valid names: \(OutputFormat.all.map { $0.name }.joined(separator: ", "))")
}

var style = RenderStyle.default
if let stylePath = options.stylePath {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: stylePath))
        style = try JSONDecoder().decode(RenderStyle.self, from: data)
    } catch {
        fail("Could not read --style \(stylePath): \(error)")
    }
}

do {
    let urls = try ExportJob.run(bundleURL: URL(fileURLWithPath: options.bundle),
                                 formats: formats, style: style,
                                 settings: AutoDirectorSettings(),
                                 outDir: URL(fileURLWithPath: options.out))
    for u in urls { print("Wrote \(u.path)") }
} catch {
    fail("Export failed: \(error)", code: 2)
}
```

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build` then `swift test`
Expected: `swift build` produces `shortscast-export`; full suite passes.

- [ ] **Step 7: Commit**

```bash
git add Sources/ShortsCastRender/ExportOptions.swift Sources/shortscast-export/main.swift Tests/ShortsCastRenderTests/ExportOptionsTests.swift
git commit -m "feat: add export CLI option parsing and shortscast-export main"
```

---

### Task 10: End-to-end manual verification

**Files:** none (verification + a short results note).

This task confirms the CLI works end-to-end on a real bundle. Since no real `.shortscast` capture exists yet (capture frame delivery is blocked on this macOS 12.6 box), build a synthetic bundle with the test factory and export it, then eyeball the MP4s.

- [ ] **Step 1: Build the release binary**

Run: `swift build -c release`
Expected: succeeds; binary at `.build/release/shortscast-export`.

- [ ] **Step 2: Create a synthetic bundle via a throwaway Swift snippet**

Run this from the repo root (it reuses the package to synthesize a bundle):

```bash
cat > /tmp/make_bundle.swift <<'SWIFT'
import Foundation
// This snippet is illustrative; in practice generate the bundle from a unit-test run
// (ExportJobTests already writes one to a temp dir). For manual export, point
// shortscast-export at any .shortscast directory containing raw.mov + events.json + meta.json.
SWIFT
echo "Use a bundle produced by the test suite or a future real capture."
```

Practical path: run the export test so it writes a bundle you can inspect, or copy the structure: a directory `X.shortscast/` containing `raw.mov`, `events.json`, `meta.json`.

- [ ] **Step 3: Export a synthetic bundle**

If you have a `.shortscast` bundle at `/tmp/clip.shortscast`:

Run: `.build/release/shortscast-export /tmp/clip.shortscast --format 9:16,1:1 --out /tmp/exports`
Expected: prints `Wrote /tmp/exports/clip-9x16.mp4` and `Wrote /tmp/exports/clip-1x1.mp4`.

- [ ] **Step 4: Inspect the output**

Run: `open /tmp/exports/clip-9x16.mp4`
Confirm: the video plays, is vertical 1080×1920, shows the screen content framed on the styled background with rounded corners + shadow, and the cursor/ripples appear where expected.

- [ ] **Step 5: Record results**

Append a short pass/fail note to the report file. If a code fix was needed, commit it and re-run the affected step.

---

## Self-Review

**Spec coverage:**
- `ShortsCastRender` lib + `shortscast-export` CLI → Task 1; Plan 2 `showsCursor=false` tweak → Task 1.
- `RenderStyle`/`RGBA` (solid + gradient, corner/shadow/padding/cursor/ripple, Codable, default) → Task 2.
- `FrameLayout` aspect-preserving padding → Task 3.
- `CursorRenderer` position interpolation + ripple selection → Task 4.
- Core Image compositing (background, cropped+scaled content, rounded corners, shadow) → Task 5; synthetic cursor + ripples → Task 6.
- `VideoExporter` (AVAssetReader→composite→AVAssetWriter, PTS preserved, errors) + synthetic test video → Task 7.
- `ExportJob` batch per format + naming → Task 8.
- CLI parse + main (`--format`/`--out`/`--style`, error exits) → Task 9.
- Manual end-to-end → Task 10.
- Testing strategy (pure unit, offline bitmap pixel assertions, synthetic-video export) → Tasks 2-9.

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step has complete Swift. Task 10's snippet is explicitly illustrative and points to the test-produced bundle (manual step, no production code).

**Type consistency:** `FrameCompositor(style:format:screenSize:)` + `composite(source:crop:time:cursor:)` consistent Tasks 5,6,7. `RenderStyle`/`RGBA` fields consistent Tasks 2,5,6,7,9. `FrameLayout.contentRect(exportSize:paddingFraction:)` consistent Tasks 3,5. `CursorRenderer.position(at:samples:)`/`activeRipples(at:clicks:duration:)` + `RippleState` consistent Tasks 4,6. `VideoExporter.export(rawVideoURL:result:format:style:screenSize:to:)` consistent Tasks 7,8. `ExportJob.run(bundleURL:formats:style:settings:outDir:)` consistent Tasks 8,9. `ExportOptions`/`ExportParseError` consistent Task 9. Reused core/capture signatures match Plan 1/2.

## Notes for Plan 4 (Editor UI)

- The editor composites a single frame for live preview by calling `FrameCompositor.composite(...)` and rendering to a `CGImage`/SwiftUI image; it reuses `ExportJob.run` for final export.
- Per-segment style and interactive controls replace the single global `RenderStyle` and the CLI flags.
- Real-bundle export verification (and the synthetic cursor visually) lands naturally once capture works on macOS 13+ in the Plan 4 app.
