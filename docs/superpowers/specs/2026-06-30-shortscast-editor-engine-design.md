# ShortsCast Editor Engine — Design Spec (Plan 4)

**Date:** 2026-06-30
**Status:** Approved design, pre-implementation
**Sub-project:** Plan 4 of the ShortsCast roadmap (Editor engine; the SwiftUI shell is Plan 5).
**Depends on:** `ShortsCastCore` (Director, DirectorResult, FocusSegment, SegmentOverride, applyOverrides, AutoDirectorSettings, OutputFormat, CursorTrack), `ShortsCastCapture` (ProjectBundle, EventLog, Recorder), `ShortsCastRender` (FrameCompositor, RenderStyle, ExportJob, VideoExporter).

## Summary

`ShortsCastEditor` is a headless, fully unit-testable editor **engine** — a single `EditorModel`
view-model that opens a `.shortscast` bundle, runs the `Director`, holds the user's edits
(per-segment zoom-× overrides, style, output format, global zoom settings), produces a live
composited **preview frame** via `FrameCompositor`, persists edits to `project.json`, and
drives **export** (honoring overrides). The SwiftUI app shell that binds to this engine is a
separate later plan (Plan 5).

The editor is split this way because SwiftUI views can't be meaningfully unit-tested and
live capture needs macOS 13+ (ScreenCaptureKit is unreliable on the macOS 12.6 dev machine).
By putting all logic in `EditorModel`, the entire editor brain is verifiable on this machine
(AVFoundation + Core Image only); the views and capture are quarantined to Plan 5.

## Goals & non-goals

In scope (Plan 4):
- `EditorModel`: open a bundle, run Director, expose `segments`/`duration`, edit (per-segment
  zoom override, clear override, global default/max zoom, format, style, selection),
  `previewImage(at:)`, persist edits to `project.json`, `export(...)`, and a thin
  `record(...)` orchestration.
- A `FrameSource` abstraction (real `AVAssetFrameSource` over `raw.mov`; a fake for tests).
- Three small additive enabling tweaks to earlier libraries (see below).

Out of scope (Plan 5 / later):
- All SwiftUI views (preview canvas, timeline, inspector, buttons, windows, .app bundle).
- Live-recording UI and its on-machine verification (macOS 13+).
- Undo/redo, multi-project management, per-segment center/pan editing UI (only zoom-× in v1),
  thumbnails/scrubbing-cache.

## Toolchain & platform

- Swift 5.7 (Xcode 14.2), same package. Platform floor `.macOS(.v12)`.
- AVFoundation + Core Image (portable, works on macOS 12.6). `record(...)` is
  `@available(macOS 12.3, *)` and excluded from automated tests.

## Module layout

New library target **`ShortsCastEditor`** depending on `ShortsCastCore`, `ShortsCastCapture`,
`ShortsCastRender`; new test target `ShortsCastEditorTests`.

| Unit | Kind | Testable |
|---|---|---|
| `ProjectEdits` — Codable: overrides + RenderStyle + formatName + AutoDirectorSettings | pure | ✅ round-trip |
| `FrameSource` (protocol) + `AVAssetFrameSource` (AVAssetImageGenerator over raw.mov) | OS adapter / abstraction | ✅ via fake; AVAsset path via synthetic video |
| `EditorModel` — ObservableObject holding state + edit/preview/persist/export/record logic | view-model | ✅ (record excluded) |

Three additive tweaks to existing libraries (folded into this plan's early tasks):
- `AutoDirectorSettings: Codable` (Core) — value-type struct; synthesized conformance.
- `SegmentOverride: Codable` (Core) — `index:Int, zoom:CGFloat?, center:CGPoint?`; synthesized.
- `ExportJob.run(...)` gains `overrides: [SegmentOverride] = []` (Render) — passed into
  `Director.direct(log:overrides:)` instead of the current hardcoded `[]`. Default value keeps
  existing callers (the CLI) working unchanged.

## EditorModel

State (all `@Published` where mutable, so Plan 5 binds directly):
- `bundleURL: URL?`, `eventLog: EventLog?`, `rawVideoURL: URL?`, `screenSize: CGSize`
- `settings: AutoDirectorSettings`, `overrides: [SegmentOverride]`, `style: RenderStyle`,
  `format: OutputFormat`, `result: DirectorResult?`, `selectedSegment: Int?`
- a cached `FrameCompositor` (rebuilt only when `style`/`format`/`screenSize` change)
- `frameSource: FrameSource?`

Derived:
- `segments: [FocusSegment]` = `result?.segments ?? []`
- `duration: Seconds` = `eventLog?.duration ?? 0`

Lifecycle / regeneration:
- `open(_ bundleURL: URL) throws`: `ProjectBundle.read` → set eventLog/rawVideoURL/screenSize;
  if `project.json` exists, decode `ProjectEdits` and apply (overrides, style, format resolved
  from `OutputFormat.all` by `formatName` — falling back to `.vertical9x16` if unknown,
  settings); else defaults (`RenderStyle.default`, `.vertical9x16`, `AutoDirectorSettings()`).
  Build `AVAssetFrameSource(rawVideoURL)`. Call `regenerate()`.
- `regenerate()`: `result = Director(settings: settings).direct(log: eventLog!, overrides: overrides)`.

Editing:
- `setZoom(segment index: Int, zoom: CGFloat)`: upsert `SegmentOverride(index:index, zoom:zoom)`
  (replace any existing override for that index), `regenerate()`.
- `clearOverride(segment index: Int)`: remove any override for that index, `regenerate()`.
- `setDefaultZoom(_ z: CGFloat)`: `settings.defaultZoom = z`, `regenerate()`.
- `setMaxZoom(_ z: CGFloat)`: `settings.maxZoom = z`, `regenerate()`.
- `setFormat(_ f: OutputFormat)`: set, invalidate compositor cache (no re-direct).
- `setStyle(_ s: RenderStyle)`: set, invalidate compositor cache.
- `selectSegment(_ index: Int?)`: set `selectedSegment`.

Preview:
- `previewImage(at t: Seconds) -> CGImage?`: guard `result`, `frameSource`, `eventLog`; get
  `source = frameSource.image(at: t)`; `crop = Director(settings: settings).cropRect(result!,
  at: t, format: format, screen: screenSize)`; obtain the cached `FrameCompositor`;
  `composed = compositor.composite(source:, crop:, time: t, cursor: result!.cursor)`; return
  `compositor.context.createCGImage(composed, from: CGRect(origin:.zero, size: format.exportSize))`.
  Returns nil if no source frame at `t`.

Persistence:
- `currentEdits() -> ProjectEdits` = `ProjectEdits(overrides:, style:, formatName: format.name, settings:)`.
- `save() throws`: encode `currentEdits()` to `<bundleURL>/project.json`.

Export:
- `export(formats: [OutputFormat], outDir: URL) throws -> [URL]`:
  `ExportJob.run(bundleURL: bundleURL!, formats: formats, style: style, settings: settings,
  outDir: outDir, overrides: overrides)`.

Recording (`@available(macOS 12.3, *)`, untested on this machine):
- `record(target: ResolvedTarget, seconds: Double, outBundle: URL, appVersion: String,
  createdISO: String) async throws`: `Recorder.record(...)` then `try open(outBundle)`.

## FrameSource

```
public protocol FrameSource { func image(at t: Seconds) -> CIImage? }

public final class AVAssetFrameSource: FrameSource {
    public init(url: URL)   // sets up AVAssetImageGenerator (appliesPreferredTrackTransform = true)
    public func image(at t: Seconds) -> CIImage?  // copyCGImage at CMTime(t) -> CIImage; nil on failure
}
```
The generator uses a tight tolerance so the previewed frame matches the scrub time closely.
Tests inject a fake `FrameSource` returning a known `CIImage` so preview compositing is
asserted by reading back pixels.

## Error handling

- `open` surfaces `ProjectBundle.read` errors (missing/invalid bundle); a malformed
  `project.json` is treated as "no saved edits" (log + start from defaults) rather than a hard
  failure, so a corrupt edit file never bricks a recording.
- An unknown `formatName` in `project.json` falls back to `.vertical9x16`.
- `export`/`save` surface their underlying errors.
- `previewImage`/editing before `open` return nil / no-op (guarded on `result`/`eventLog`).

## Testing & verification

Fully on this machine (AVFoundation + Core Image; synthetic video via `TestVideoFactory`,
which is promoted from the render tests to a shared test helper or re-created in the editor
tests):
- **Open/state:** synthetic `.shortscast` (TestVideoFactory `raw.mov` + hand-built `EventLog`
  with clicks) → `open` → assert `segments.count`/`duration`; `result` non-nil.
- **Editing:** `setZoom(segment:0, zoom: 3.7)` → segment 0's effective zoom is 3.7 and the
  camera path reflects it; `clearOverride(0)` reverts; `setMaxZoom`/`setDefaultZoom` shift
  generated zooms.
- **Persistence:** `ProjectEdits` JSON round-trip; open→edit→`save()`→fresh `EditorModel`.open
  → overrides/style/formatName/settings restored.
- **Preview:** fake `FrameSource` (solid + two-tone) → `previewImage(at:)` → sample returned
  `CGImage`: background color at edge, content at center, top/bottom two-tone reconfirms
  orientation through the editor path.
- **Export integration:** `export([.vertical9x16, .square1x1], outDir)` → two MP4s with exact
  dimensions; an export WITH a per-segment override differs from one without (proving
  overrides reach export through the new `ExportJob` parameter).
- **Excluded:** `record(...)` (verified in Plan 5 on macOS 13+) and all SwiftUI.

## Interfaces produced (for Plan 5)

- `EditorModel` (ObservableObject) — Plan 5's SwiftUI views bind to its `@Published` state and
  call its edit/preview/persist/export/record methods. `previewImage(at:)` feeds the preview
  canvas; `segments`/`selectedSegment`/`setZoom` feed the timeline; `style`/`setStyle` feed the
  inspector; `format`/`setFormat` feed the format switcher; `export`/`record` back the buttons.
