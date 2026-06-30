# ShortsCast Editor App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `shortscast-app` — a macOS SwiftUI app that binds thin, declarative views to the already-tested `EditorModel` (open a `.shortscast`, scrub a live preview, edit per-segment zoom + style + format on a timeline/inspector, record, and export), packaged as a signed `.app`.

**Architecture:** All logic stays in `EditorModel`; views are thin bindings. The only logic-bearing UI code (timeline geometry, time formatting) lives as pure functions in the `ShortsCastEditor` library and is unit-tested. SwiftUI views are verified by `swift build` + manual run. Live capture (Record) is `@available(macOS 12.3)` and only functional on macOS 13+.

**Tech Stack:** Swift 5.7 (Xcode 14.2), SwiftPM, SwiftUI, AppKit (`NSOpenPanel`, `NSWorkspace`, `NSColor`), XCTest (helpers only).

## Global Constraints

- Swift tools `5.7`; package platform floor `.macOS(.v12)`.
- New executable target `shortscast-app` depends on `ShortsCastEditor`, `ShortsCastCore`, `ShortsCastCapture`, `ShortsCastRender`. The `@main App` lives in a file NOT named `main.swift` (Swift forbids `@main` + `main.swift` together).
- The two pure helpers (`TimelineLayout`, `TimeLabel`) live in `Sources/ShortsCastEditor/` and are unit-tested in `Tests/ShortsCastEditorTests/`. SwiftUI views are not unit-tested.
- **Execution rhythm note:** view tasks (4-8) are gated by "`swift build` succeeds + the described manual run," NOT by test assertions. Only Tasks 1-2 are TDD. Reviewers verify view tasks by reading the code and confirming the build.
- Record (`EditorModel.record` / `TargetResolver` / `Recorder`) is `@available(macOS 12.3, *)`; its UI is availability-gated and only functional on macOS 13+ (capture yields no frames on the 12.6 dev machine).
- Reused `EditorModel` surface (verbatim): `open(_:) throws`; `save() throws`; `export(formats:outDir:) throws -> [URL]`; `@available(macOS 12.3,*) record(target:seconds:outBundle:appVersion:createdISO:) async throws`; `previewImage(at: Seconds) -> CGImage?`; `setZoom(segment:zoom:)`; `clearOverride(segment:)`; `@Published var selectedSegment: Int?`; `@Published var style: RenderStyle`; `@Published var format: OutputFormat`; `@Published var settings: AutoDirectorSettings`; `var segments: [FocusSegment]`; `var duration: Seconds`; `@Published private(set) var result/overrides/bundleURL/...`. `FocusSegment { start, end, center, zoom }`. `OutputFormat { name, exportSize, aspectRatio, static all }`. `RenderStyle { background: .solid(RGBA)/.gradient(top:bottom:), cornerRadius, shadowOpacity, shadowBlur, shadowOffsetY, paddingFraction, cursorRadius, cursorColor, rippleDuration, rippleMaxRadius }`. `RGBA(_ r:_ g:_ b:_ a:)`.

---

### Task 1: TimelineLayout (pure geometry)

**Files:**
- Create: `Sources/ShortsCastEditor/TimelineLayout.swift`
- Test: `Tests/ShortsCastEditorTests/TimelineLayoutTests.swift`

**Interfaces:**
- Consumes: `FocusSegment` (core).
- Produces: `enum TimelineLayout { static func xPositions(segments: [FocusSegment], duration: Seconds, width: CGFloat, height: CGFloat) -> [CGRect] }` — maps each segment's `[start,end]` time range to a rect `(x = start/duration*width, w = (end-start)/duration*width, y = 0, h = height)`, clamped so the rect stays within `[0,width]`. Returns `[]` (per-segment empty is not produced; the array is index-aligned) when `duration <= 0`. Rects align index-for-index with `segments`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/TimelineLayoutTests.swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastEditor

final class TimelineLayoutTests: XCTestCase {
    private func seg(_ s: Double, _ e: Double) -> FocusSegment {
        FocusSegment(start: s, end: e, center: .zero, zoom: 2)
    }
    func test_mapsTimeRangesToRects() {
        let rects = TimelineLayout.xPositions(segments: [seg(0, 2), seg(5, 10)],
                                              duration: 10, width: 100, height: 20)
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].minX, 0, accuracy: 1e-6)
        XCTAssertEqual(rects[0].width, 20, accuracy: 1e-6)   // (2-0)/10*100
        XCTAssertEqual(rects[1].minX, 50, accuracy: 1e-6)    // 5/10*100
        XCTAssertEqual(rects[1].width, 50, accuracy: 1e-6)   // (10-5)/10*100
        XCTAssertEqual(rects[0].height, 20, accuracy: 1e-6)
    }
    func test_clampsToWidth() {
        let rects = TimelineLayout.xPositions(segments: [seg(8, 20)], duration: 10, width: 100, height: 10)
        XCTAssertGreaterThanOrEqual(rects[0].minX, 0)
        XCTAssertLessThanOrEqual(rects[0].maxX, 100 + 1e-6) // clamped even though end>duration
    }
    func test_zeroDurationReturnsEmpty() {
        XCTAssertTrue(TimelineLayout.xPositions(segments: [seg(0, 1)], duration: 0, width: 100, height: 10).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TimelineLayoutTests`
Expected: FAIL — `TimelineLayout` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastEditor/TimelineLayout.swift
import Foundation
import CoreGraphics
import ShortsCastCore

/// Pure geometry: maps focus segments to x-positioned rects within a timeline band.
public enum TimelineLayout {
    public static func xPositions(segments: [FocusSegment], duration: Seconds,
                                  width: CGFloat, height: CGFloat) -> [CGRect] {
        guard duration > 0, width > 0 else { return [] }
        return segments.map { seg in
            let x0 = max(0, min(CGFloat(seg.start / duration) * width, width))
            let x1 = max(0, min(CGFloat(seg.end / duration) * width, width))
            return CGRect(x: x0, y: 0, width: max(0, x1 - x0), height: height)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TimelineLayoutTests`
Expected: PASS — all three cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastEditor/TimelineLayout.swift Tests/ShortsCastEditorTests/TimelineLayoutTests.swift
git commit -m "feat: add TimelineLayout segment geometry"
```

---

### Task 2: TimeLabel (pure formatting)

**Files:**
- Create: `Sources/ShortsCastEditor/TimeLabel.swift`
- Test: `Tests/ShortsCastEditorTests/TimeLabelTests.swift`

**Interfaces:**
- Produces: `enum TimeLabel { static func format(_ seconds: Double) -> String }` — `m:ss`; negatives clamp to "0:00".

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ShortsCastEditorTests/TimeLabelTests.swift
import XCTest
@testable import ShortsCastEditor

final class TimeLabelTests: XCTestCase {
    func test_formatsMinutesSeconds() {
        XCTAssertEqual(TimeLabel.format(0), "0:00")
        XCTAssertEqual(TimeLabel.format(3), "0:03")
        XCTAssertEqual(TimeLabel.format(63.4), "1:03")
        XCTAssertEqual(TimeLabel.format(125), "2:05")
    }
    func test_negativeClampsToZero() {
        XCTAssertEqual(TimeLabel.format(-5), "0:00")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TimeLabelTests`
Expected: FAIL — `TimeLabel` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/ShortsCastEditor/TimeLabel.swift
import Foundation

/// Pure formatting: seconds -> "m:ss".
public enum TimeLabel {
    public static func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TimeLabelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastEditor/TimeLabel.swift Tests/ShortsCastEditorTests/TimeLabelTests.swift
git commit -m "feat: add TimeLabel time formatting"
```

---

### Task 3: App target scaffold + color glue

**Files:**
- Modify: `Package.swift`
- Create: `Sources/shortscast-app/App.swift`
- Create: `Sources/shortscast-app/ColorGlue.swift`

**Interfaces:**
- Consumes: `EditorModel` (editor), `RGBA` (render).
- Produces: executable product/target `shortscast-app`; `@main struct ShortsCastApp: App` owning `@StateObject var model = EditorModel()`; a `RootView` placeholder; `Color(_ rgba: RGBA)` and `func rgba(from: Color) -> RGBA` glue.

- [ ] **Step 1: Update the manifest**

Add to `products`:
```swift
        .executable(name: "shortscast-app", targets: ["shortscast-app"]),
```
Add to `targets`:
```swift
        .executableTarget(name: "shortscast-app", dependencies: ["ShortsCastEditor", "ShortsCastCore", "ShortsCastCapture", "ShortsCastRender"]),
```

- [ ] **Step 2: Create the color glue**

```swift
// Sources/shortscast-app/ColorGlue.swift
import SwiftUI
import AppKit
import ShortsCastRender

extension Color {
    init(_ rgba: RGBA) {
        self = Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

func rgba(from color: Color) -> RGBA {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
    return RGBA(Double(ns.redComponent), Double(ns.greenComponent),
                Double(ns.blueComponent), Double(ns.alphaComponent))
}
```

- [ ] **Step 3: Create the app entry + placeholder RootView**

```swift
// Sources/shortscast-app/App.swift
import SwiftUI
import ShortsCastEditor

@main
struct ShortsCastApp: App {
    @StateObject private var model = EditorModel()
    var body: some Scene {
        WindowGroup("ShortsCast") {
            RootView(model: model)
                .frame(minWidth: 960, minHeight: 640)
        }
    }
}

struct RootView: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            Text("ShortsCast — open a recording to begin")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(.secondary)
        }
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: succeeds; the `shortscast-app` executable is produced. Run `swift test` to confirm the full suite (116 with Tasks 1-2) still passes.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/shortscast-app
git commit -m "feat: scaffold shortscast-app SwiftUI target"
```

---

### Task 4: Toolbar Open + live Preview

**Files:**
- Create: `Sources/shortscast-app/PreviewView.swift`
- Create: `Sources/shortscast-app/ToolbarView.swift`
- Modify: `Sources/shortscast-app/App.swift` (RootView)

**Interfaces:**
- Consumes: `EditorModel.open`, `previewImage(at:)`, `duration`, `format`.
- Produces: `ToolbarView` (with an Open button using `NSOpenPanel`); `PreviewView` (scrubber + play/pause + rendered frame); RootView now shows toolbar above the preview. After this task, the app can Open a bundle and scrub the preview.

- [ ] **Step 1: Create PreviewView**

```swift
// Sources/shortscast-app/PreviewView.swift
import SwiftUI
import ShortsCastEditor

struct PreviewView: View {
    @ObservedObject var model: EditorModel
    @Binding var currentTime: Double
    @State private var timer: Timer?
    @State private var playing = false

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let cg = model.previewImage(at: currentTime) {
                    Image(decorative: cg, scale: 1.0)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle().fill(Color.black.opacity(0.85))
                        .overlay(Text("No preview").foregroundColor(.white.opacity(0.6)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button(action: togglePlay) {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                }
                Slider(value: $currentTime, in: 0...max(model.duration, 0.001))
                Text(TimeLabel.format(currentTime)).monospacedDigit().frame(width: 48)
            }
        }
        .padding(8)
        .onDisappear { timer?.invalidate() }
    }

    private func togglePlay() {
        playing.toggle()
        timer?.invalidate()
        guard playing else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            let next = currentTime + 1.0 / 30.0
            if next >= model.duration { currentTime = model.duration; playing = false; timer?.invalidate() }
            else { currentTime = next }
        }
    }
}
```

- [ ] **Step 2: Create ToolbarView (Open)**

```swift
// Sources/shortscast-app/ToolbarView.swift
import SwiftUI
import AppKit
import ShortsCastEditor

struct ToolbarView: View {
    @ObservedObject var model: EditorModel
    @Binding var currentTime: Double
    @Binding var errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            Button("Open") { openBundle() }
            Spacer()
        }
        .padding(8)
    }

    private func openBundle() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a .shortscast bundle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.open(url); currentTime = 0 }
        catch { errorMessage = "Open failed: \(error)" }
    }
}
```

- [ ] **Step 3: Wire RootView**

Replace `RootView` in `App.swift` with:
```swift
struct RootView: View {
    @ObservedObject var model: EditorModel
    @State private var currentTime: Double = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(model: model, currentTime: $currentTime, errorMessage: $errorMessage)
            Divider()
            PreviewView(model: model, currentTime: $currentTime)
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil },
                                             set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
```

- [ ] **Step 4: Build + manual check**

Run: `swift build`
Expected: compiles. (Manual, after Task 9 packaging: Open `/tmp/shortscast-demo/demo.shortscast` and confirm the preview renders and scrubs.)

- [ ] **Step 5: Commit**

```bash
git add Sources/shortscast-app
git commit -m "feat: app toolbar Open + live preview scrubbing"
```

---

### Task 5: TimelineView

**Files:**
- Create: `Sources/shortscast-app/TimelineView.swift`
- Modify: `Sources/shortscast-app/App.swift` (RootView)

**Interfaces:**
- Consumes: `TimelineLayout.xPositions` (Task 1), `EditorModel.segments`, `duration`, `selectedSegment`.
- Produces: `TimelineView` drawing segment blocks (selectable) + a playhead; wired into RootView's bottom.

- [ ] **Step 1: Create TimelineView**

```swift
// Sources/shortscast-app/TimelineView.swift
import SwiftUI
import ShortsCastEditor

struct TimelineView: View {
    @ObservedObject var model: EditorModel
    @Binding var currentTime: Double
    private let band: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let rects = TimelineLayout.xPositions(segments: model.segments,
                                                  duration: model.duration, width: w, height: band)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.gray.opacity(0.15))
                ForEach(Array(rects.enumerated()), id: \.offset) { idx, r in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(model.selectedSegment == idx ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .frame(width: max(2, r.width), height: r.height)
                        .offset(x: r.minX, y: 0)
                        .onTapGesture { model.selectedSegment = idx }
                }
                if model.duration > 0 {
                    Rectangle().fill(Color.red).frame(width: 2, height: band)
                        .offset(x: CGFloat(currentTime / model.duration) * w, y: 0)
                }
            }
        }
        .frame(height: band)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 2: Wire RootView**

In `RootView.body`, add the timeline below the preview (between `PreviewView(...)` and the closing of the outer `VStack`):
```swift
            Divider()
            TimelineView(model: model, currentTime: $currentTime)
```

- [ ] **Step 3: Build + manual check**

Run: `swift build`
Expected: compiles. (Manual: after opening a bundle, segment blocks appear; clicking one selects it; the playhead tracks the scrubber.)

- [ ] **Step 4: Commit**

```bash
git add Sources/shortscast-app
git commit -m "feat: app timeline with selectable segments and playhead"
```

---

### Task 6: InspectorView

**Files:**
- Create: `Sources/shortscast-app/InspectorView.swift`
- Modify: `Sources/shortscast-app/App.swift` (RootView middle becomes an HSplitView)

**Interfaces:**
- Consumes: `EditorModel.format/style/settings/selectedSegment/segments/setZoom/clearOverride`, `OutputFormat.all`, `RGBA`, color glue (Task 3).
- Produces: `InspectorView` with format picker, background mode + colors, corner/shadow/padding sliders, global default/max zoom, and selected-segment zoom-× + reset; RootView wraps Preview + Inspector in an `HSplitView`.

- [ ] **Step 1: Create InspectorView**

```swift
// Sources/shortscast-app/InspectorView.swift
import SwiftUI
import ShortsCastEditor
import ShortsCastCore
import ShortsCastRender

struct InspectorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        Form {
            Section("Format") {
                Picker("Aspect", selection: Binding(
                    get: { model.format.name },
                    set: { name in if let f = OutputFormat.all.first(where: { $0.name == name }) { model.format = f } })) {
                    ForEach(OutputFormat.all, id: \.name) { Text($0.name).tag($0.name) }
                }
            }
            Section("Background") {
                Picker("Mode", selection: Binding(get: { isGradient ? 1 : 0 }, set: { setGradient($0 == 1) })) {
                    Text("Solid").tag(0); Text("Gradient").tag(1)
                }
                if isGradient {
                    ColorPicker("Top", selection: gradientTopBinding)
                    ColorPicker("Bottom", selection: gradientBottomBinding)
                } else {
                    ColorPicker("Color", selection: solidBinding)
                }
            }
            Section("Framing") {
                slider("Corner", \.cornerRadius, 0...80)
                slider("Shadow", \.shadowOpacity, 0...1)
                slider("Padding", \.paddingFraction, 0...0.3)
            }
            Section("Auto-zoom") {
                zoomSlider("Default ×", \.defaultZoom, 1...5)
                zoomSlider("Max ×", \.maxZoom, 1...6)
            }
            if let sel = model.selectedSegment, sel < model.segments.count {
                Section("Selected segment") {
                    Slider(value: Binding(
                        get: { Double(model.segments[sel].zoom) },
                        set: { model.setZoom(segment: sel, zoom: CGFloat($0)) }), in: 1...6)
                    Button("Reset") { model.clearOverride(segment: sel) }
                }
            }
        }
        .frame(width: 260)
        .padding(8)
    }

    private var isGradient: Bool { if case .gradient = model.style.background { return true }; return false }
    private func setGradient(_ on: Bool) {
        if on { model.style.background = .gradient(top: RGBA(0.16,0.18,0.30,1), bottom: RGBA(0.05,0.06,0.12,1)) }
        else { model.style.background = .solid(RGBA(0.08,0.09,0.14,1)) }
    }
    private var solidBinding: Binding<Color> {
        Binding(get: { if case .solid(let c) = model.style.background { return Color(c) }; return .black },
                set: { model.style.background = .solid(rgba(from: $0)) })
    }
    private var gradientTopBinding: Binding<Color> {
        Binding(get: { if case .gradient(let t, _) = model.style.background { return Color(t) }; return .blue },
                set: { if case .gradient(_, let b) = model.style.background { model.style.background = .gradient(top: rgba(from: $0), bottom: b) } })
    }
    private var gradientBottomBinding: Binding<Color> {
        Binding(get: { if case .gradient(_, let b) = model.style.background { return Color(b) }; return .black },
                set: { if case .gradient(let t, _) = model.style.background { model.style.background = .gradient(top: t, bottom: rgba(from: $0)) } })
    }
    private func slider(_ label: String, _ key: WritableKeyPath<RenderStyle, CGFloat>, _ range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { Double(model.style[keyPath: key]) },
                              set: { model.style[keyPath: key] = CGFloat($0) }), in: range) { Text(label) }
    }
    private func slider(_ label: String, _ key: WritableKeyPath<RenderStyle, Double>, _ range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { model.style[keyPath: key] },
                              set: { model.style[keyPath: key] = $0 }), in: range) { Text(label) }
    }
    private func zoomSlider(_ label: String, _ key: WritableKeyPath<AutoDirectorSettings, CGFloat>, _ range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { Double(model.settings[keyPath: key]) },
                              set: { model.settings[keyPath: key] = CGFloat($0) }), in: range) { Text(label) }
    }
}
```

- [ ] **Step 2: Wire RootView (HSplitView)**

In `RootView.body`, replace the `PreviewView(model: model, currentTime: $currentTime)` line with:
```swift
            HSplitView {
                PreviewView(model: model, currentTime: $currentTime)
                InspectorView(model: model)
            }
```

- [ ] **Step 3: Build + manual check**

Run: `swift build`
Expected: compiles. (Manual: changing format reframes the preview; editing background/corner/padding/zoom updates it; selecting a segment shows its zoom-× slider; Reset reverts.)

- [ ] **Step 4: Commit**

```bash
git add Sources/shortscast-app
git commit -m "feat: app inspector for format, style, and zoom"
```

---

### Task 7: Save + Export

**Files:**
- Create: `Sources/shortscast-app/ExportSheet.swift`
- Modify: `Sources/shortscast-app/ToolbarView.swift`

**Interfaces:**
- Consumes: `EditorModel.save`, `export(formats:outDir:)`, `OutputFormat.all`.
- Produces: a Save button (calls `model.save()`); an Export button presenting `ExportSheet` (format checkboxes + output dir), which runs `model.export` off the main thread with a progress indicator and reveals results in Finder.

- [ ] **Step 1: Create ExportSheet**

```swift
// Sources/shortscast-app/ExportSheet.swift
import SwiftUI
import AppKit
import ShortsCastEditor
import ShortsCastCore

struct ExportSheet: View {
    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?
    @State private var selected: Set<String> = []
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export formats").font(.headline)
            ForEach(OutputFormat.all, id: \.name) { fmt in
                Toggle(fmt.name, isOn: Binding(
                    get: { selected.contains(fmt.name) },
                    set: { if $0 { selected.insert(fmt.name) } else { selected.remove(fmt.name) } }))
            }
            HStack {
                Button("Cancel") { isPresented = false }.disabled(exporting)
                Spacer()
                if exporting { ProgressView().scaleEffect(0.6) }
                Button("Export…") { startExport() }.disabled(exporting || selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear { if selected.isEmpty { selected = [model.format.name] } }
    }

    private func startExport() {
        let formats = OutputFormat.all.filter { selected.contains($0.name) }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Choose an output folder"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        exporting = true
        Task {
            do {
                let urls = try model.export(formats: formats, outDir: dir)
                await MainActor.run {
                    exporting = false; isPresented = false
                    if let first = urls.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
                }
            } catch {
                await MainActor.run { exporting = false; errorMessage = "Export failed: \(error)" }
            }
        }
    }
}
```

- [ ] **Step 2: Add Save + Export to the toolbar**

Replace `ToolbarView` with:
```swift
// Sources/shortscast-app/ToolbarView.swift
import SwiftUI
import AppKit
import ShortsCastEditor

struct ToolbarView: View {
    @ObservedObject var model: EditorModel
    @Binding var currentTime: Double
    @Binding var errorMessage: String?
    @State private var showExport = false

    var body: some View {
        HStack(spacing: 12) {
            Button("Open") { openBundle() }
            Button("Save") { save() }.disabled(model.bundleURL == nil)
            Spacer()
            Button("Export") { showExport = true }.disabled(model.result == nil)
        }
        .padding(8)
        .sheet(isPresented: $showExport) {
            ExportSheet(model: model, isPresented: $showExport, errorMessage: $errorMessage)
        }
    }

    private func openBundle() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a .shortscast bundle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.open(url); currentTime = 0 }
        catch { errorMessage = "Open failed: \(error)" }
    }

    private func save() {
        do { try model.save() } catch { errorMessage = "Save failed: \(error)" }
    }
}
```

- [ ] **Step 3: Build + manual check**

Run: `swift build`
Expected: compiles. (Manual: Save writes project.json; Export with formats checked produces MP4s and reveals them in Finder.)

- [ ] **Step 4: Commit**

```bash
git add Sources/shortscast-app
git commit -m "feat: app Save and Export (background export + Finder reveal)"
```

---

### Task 8: Record sheet (macOS 12.3+)

**Files:**
- Create: `Sources/shortscast-app/RecordSheet.swift`
- Modify: `Sources/shortscast-app/ToolbarView.swift`

**Interfaces:**
- Consumes: `EditorModel.record`, `TargetResolver.resolve` (capture), `ShortsCastCapture` version.
- Produces: a Record button (gated to macOS 12.3+) presenting `RecordSheet` — a seconds field + Record button that resolves a full-display target and calls `await model.record(...)`, writing to a chosen bundle path then reopening it.

- [ ] **Step 1: Create RecordSheet**

```swift
// Sources/shortscast-app/RecordSheet.swift
import SwiftUI
import AppKit
import ShortsCastEditor
import ShortsCastCapture

@available(macOS 12.3, *)
struct RecordSheet: View {
    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?
    @Binding var currentTime: Double
    @State private var seconds: Double = 5
    @State private var recording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New recording (main display)").font(.headline)
            HStack { Text("Duration"); Slider(value: $seconds, in: 2...30); Text("\(Int(seconds))s").frame(width: 36) }
            HStack {
                Button("Cancel") { isPresented = false }.disabled(recording)
                Spacer()
                if recording { ProgressView().scaleEffect(0.6) }
                Button("Record") { start() }.disabled(recording)
            }
        }
        .padding(20).frame(width: 320)
    }

    private func start() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "recording.shortscast"
        panel.message = "Save the recording bundle"
        guard panel.runModal() == .OK, let out = panel.url else { return }
        recording = true
        Task {
            do {
                let target = try await TargetResolver.resolve(displayIndex: nil, windowQuery: nil, region: nil)
                try await model.record(target: target, seconds: seconds, outBundle: out,
                                       appVersion: ShortsCastCapture.version,
                                       createdISO: ISO8601DateFormatter().string(from: Date()))
                await MainActor.run { recording = false; isPresented = false; currentTime = 0 }
            } catch {
                await MainActor.run { recording = false; errorMessage = "Record failed: \(error)" }
            }
        }
    }
}
```

- [ ] **Step 2: Add the Record button (gated)**

In `ToolbarView`, add `@State private var showRecord = false` and, in the `HStack` after the Save button:
```swift
            if #available(macOS 12.3, *) {
                Button("Record") { showRecord = true }
            } else {
                Button("Record") {}.disabled(true).help("Recording requires macOS 12.3+")
            }
```
Add `@Binding var currentTime` is already present. Add the sheet modifier after the existing `.sheet(isPresented: $showExport)`:
```swift
        .sheet(isPresented: $showRecord) {
            if #available(macOS 12.3, *) {
                RecordSheet(model: model, isPresented: $showRecord, errorMessage: $errorMessage, currentTime: $currentTime)
            }
        }
```

- [ ] **Step 3: Build + manual check**

Run: `swift build`
Expected: compiles. (Manual on macOS 13+: Record captures the main display for N seconds, writes a bundle, and reopens it into the editor. On macOS 12.6 the sheet presents but yields no frames — verified later.)

- [ ] **Step 4: Commit**

```bash
git add Sources/shortscast-app
git commit -m "feat: app Record sheet (macOS 12.3+ full-display capture)"
```

---

### Task 9: Package the app (.app bundle)

**Files:**
- Modify: `Scripts/make-app.sh`

**Interfaces:**
- Produces: `Scripts/make-app.sh` also builds `shortscast-app` and wraps it into `.build/ShortsCastApp.app` (Info.plist + ad-hoc sign), alongside the existing `shortscast-rec` CLI `.app`.

- [ ] **Step 1: Extend the script**

Append to `Scripts/make-app.sh` (after the existing `shortscast-rec` packaging, before the final echo if any — keep the existing content):
```bash

# --- GUI editor app ---
APP="$ROOT/.build/ShortsCastApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/shortscast-app" "$APP/Contents/MacOS/shortscast-app"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.shortscast.app</string>
  <key>CFBundleName</key><string>ShortsCast</string>
  <key>CFBundleExecutable</key><string>shortscast-app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
echo "Launch the editor: open $APP"
```
(Ensure the script's existing `swift build -c release` builds all products, which it does; `shortscast-app` is included automatically.)

- [ ] **Step 2: Run the script**

Run: `./Scripts/make-app.sh`
Expected: builds release, prints `Built …/ShortsCastApp.app`. Verify: `codesign -dv .build/ShortsCastApp.app` shows `Identifier=com.shortscast.app`.

- [ ] **Step 3: Commit**

```bash
git add Scripts/make-app.sh
git commit -m "chore: package shortscast-app into a signed .app"
```

---

### Task 10: Manual end-to-end verification

**Files:** none (verification + a short results note).

This task is run by a human; it verifies the SwiftUI app that unit tests cannot.

- [ ] **Step 1: Launch the app**

Run: `./Scripts/make-app.sh && open .build/ShortsCastApp.app`
Expected: a window opens with the toolbar and an empty preview placeholder.

- [ ] **Step 2: Open the demo bundle and scrub**

In the app: Open → choose `/tmp/shortscast-demo/demo.shortscast` (generate it first if absent via the demo path used previously). Confirm: the preview renders the framed 9:16 composite; dragging the slider scrubs; Play advances the playhead; the timeline shows segment blocks.

- [ ] **Step 3: Edit**

Select a segment block → its zoom-× slider appears; drag it and confirm the preview's zoom changes. Change Format to 1:1 and confirm reframing. Adjust background/corner/padding and confirm live updates.

- [ ] **Step 4: Save + Export**

Click Save (confirm `project.json` appears in the bundle). Click Export → check 9:16 + 1:1 → choose an output folder → confirm two MP4s are produced and revealed in Finder, and they play correctly.

- [ ] **Step 5: Record (macOS 13+ only)**

On a macOS 13+ machine: grant the app Screen Recording, click Record → set seconds → Record → confirm it captures the main display, writes a bundle, and reopens it with real content. (On macOS 12.6 this step is expected to produce no frames.)

- [ ] **Step 6: Record results**

Append a short pass/fail note per step to the report file. If a code fix was needed, commit it and re-run the affected step.

---

## Self-Review

**Spec coverage:**
- Pure helpers `TimelineLayout`/`TimeLabel` (the testable core) → Tasks 1-2.
- `shortscast-app` target + `@main App` + color glue → Task 3.
- Toolbar Open + Preview (scrub + play) → Task 4. Timeline (selectable segments + playhead) → Task 5. Inspector (format/background/framing/zoom/selected-segment) → Task 6. Save + Export (background + Finder reveal) → Task 7. Record (gated, full-display) → Task 8.
- `.app` packaging via `make-app.sh` → Task 9. Manual end-to-end → Task 10.

**Placeholder scan:** No TBD/TODO; complete Swift in every code step. View tasks are explicitly gated by `swift build` + manual run (documented in Global Constraints), not vacuous tests.

**Type consistency:** Views bind to the documented `EditorModel` surface (`open`/`save`/`export`/`record`/`previewImage`/`setZoom`/`clearOverride`/`selectedSegment`/`segments`/`duration`/`style`/`format`/`settings`/`result`/`bundleURL`). `TimelineLayout.xPositions(segments:duration:width:height:)` signature matches between Task 1 and Task 5. `TimeLabel.format(_:)` matches between Task 2 and Task 4. `RGBA(_:_:_:_:)` + color glue (Task 3) used in Task 6. `OutputFormat.all`/`.name` used in Tasks 6/7. `TargetResolver.resolve(displayIndex:windowQuery:region:)` + `Recorder` reused in Task 8 match Plan 2.

## Notes

- This completes the ShortsCast roadmap (Plans 1-5). The remaining genuinely-unverified surface — live screen capture and the aesthetic review of a real recording — is exercised by Task 10 Step 5 on macOS 13+.
- Window/region capture pickers, audio, webcam, undo/redo, and real-time playback remain future enhancements beyond this plan.
