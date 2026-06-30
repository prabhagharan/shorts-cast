# ShortsCast Editor App — Design Spec (Plan 5)

**Date:** 2026-06-30
**Status:** Approved design, pre-implementation
**Sub-project:** Plan 5 of the ShortsCast roadmap (the SwiftUI app shell — the finale).
**Depends on:** `ShortsCastEditor` (`EditorModel`, `FrameSource`, `ProjectEdits`) and transitively `ShortsCastCore`/`ShortsCastCapture`/`ShortsCastRender`.

## Summary

A macOS SwiftUI app (`shortscast-app`) that binds thin, declarative views to the already-built,
already-tested `EditorModel`. It opens a `.shortscast` bundle, shows a live composited preview,
a timeline of auto-zoom focus segments with per-segment zoom-× editing, a style/format inspector,
and toolbar actions for New Recording, Open, Save, and Export. The app is built as a SwiftPM
executable and wrapped into a signed `.app` bundle.

Because all logic lives in `EditorModel` (114 tests), the views are thin. The genuinely
logic-bearing UI helpers (timeline geometry, time formatting) are extracted into pure,
unit-tested functions. SwiftUI views themselves are verified by building and running the app.
Live screen capture (the Record flow) is verifiable only on macOS 13+ (ScreenCaptureKit is
unreliable on the macOS 12.6 dev machine); everything else — open, preview, edit, save, export —
runs and is manually verifiable on this machine.

## Goals & non-goals

In scope:
- `shortscast-app` SwiftUI executable + `.app` packaging (extend `Scripts/make-app.sh`).
- Window: toolbar (Open/Record/Save/Export); middle split of Preview (left) + Inspector (right);
  bottom Timeline.
- Preview: scrub via a slider over `0...duration` rendering `EditorModel.previewImage(at:)`;
  best-effort play/pause that advances the scrubber on a timer.
- Timeline: segments laid out by time; tap to select; playhead; selected-segment zoom-× edit.
- Inspector: format picker; background (solid/gradient + colors); corner/shadow/padding sliders;
  global default/max zoom; selected-segment zoom-× slider + reset.
- Toolbar actions wired to `EditorModel`: `open`, `save`, `export` (format multi-select + output
  dir, run off the main thread with progress), `record` (full-display, N seconds).
- Pure, unit-tested view helpers: `TimelineLayout.xPositions(...)`, `TimeLabel.format(...)`.

Out of scope (later):
- Window/region capture pickers (v1 records the full main display); live preview during capture.
- Audio, webcam overlay, wallpaper-image backgrounds, per-segment center/pan editing UI.
- Undo/redo, multi-window/document model, thumbnail scrubbing cache, real-time (audio-synced)
  playback.

## Toolchain & platform

- Swift 5.7 (Xcode 14.2), same package. Platform floor `.macOS(.v12)`.
- SwiftUI + AppKit (`NSOpenPanel`, Finder reveal). The Record flow uses
  `ShortsCastCapture.Recorder`/`TargetResolver` (`@available(macOS 12.3, *)`); the recording UI is
  availability-gated and only functional on macOS 13+.

## Module layout

New SwiftUI executable target **`shortscast-app`** depending on `ShortsCastEditor`,
`ShortsCastCore`, `ShortsCastCapture`, `ShortsCastRender`; new test target
`ShortsCastAppTests` (covers only the pure helpers).

| Unit | Kind | Testable |
|---|---|---|
| `TimelineLayout.xPositions(segments:duration:width:) -> [CGRect]` | pure geometry | ✅ unit |
| `TimeLabel.format(_ seconds: Double) -> String` ("0:03") | pure | ✅ unit |
| `ShortsCastApp` (`@main App`), `RootView`, `PreviewView`, `TimelineView`, `InspectorView`, `Toolbar`, `ExportSheet`, `RecordSheet` | SwiftUI views | build + manual run |

The app owns one `@StateObject var model = EditorModel()`; views read its `@Published` state and
call its methods. No business logic is duplicated in the views.

## Views & interaction

**RootView:** `VStack { ToolbarView; HSplitView { PreviewView; InspectorView }; TimelineView }`.

**PreviewView:**
- `@State currentTime: Double`. A `Slider(value:$currentTime, in: 0...max(model.duration, 0.001))`
  drives it. The view renders `model.previewImage(at: currentTime)` (a `CGImage`) into an `Image`,
  fit to `model.format` aspect. A nil image (nothing open) shows a placeholder.
- Play/pause toggle starts/stops a `Timer` (~30 fps) advancing `currentTime` by the tick interval,
  clamped to `duration`, stopping at the end. This is preview playback (frame re-render per tick),
  not audio-synced.

**TimelineView:**
- Lays out `model.segments` as blocks using `TimelineLayout.xPositions(segments:duration:width:)`
  in a `GeometryReader`. Tapping a block sets `model.selectedSegment`; the selected block is
  highlighted. A vertical playhead reflects `currentTime`. A `TimeLabel.format(currentTime)` label
  is shown.

**InspectorView** (all bindings assign mutated value-type copies so `didSet` fires):
- Format: `Picker` over `OutputFormat.all` (by `name`) → `model.format`.
- Background: solid/gradient `Picker` + `ColorPicker`(s) → `model.style.background`.
- Corner radius / shadow opacity / padding fraction: `Slider`s → `model.style` fields.
- Global zoom: default/max `Slider`s → `model.settings.defaultZoom` / `.maxZoom`.
- Selected segment: when `model.selectedSegment` is non-nil, a zoom-× `Slider` →
  `model.setZoom(segment:zoom:)` and a "Reset" button → `model.clearOverride(segment:)`.

**ToolbarView:** Open, Record, Save, Export buttons (described below).

## Toolbar actions

- **Open:** `NSOpenPanel` configured for choosing a directory (`.shortscast` bundle) →
  `try model.open(url)`; on throw, present an error alert. Resets `currentTime = 0`.
- **Save:** `try model.save()`; show a brief confirmation, or an error alert on throw.
- **Export:** present `ExportSheet` — checkboxes over `OutputFormat.all` (default the current
  format checked) and an `NSOpenPanel`-chosen output directory. On confirm, run
  `try model.export(formats:outDir:)` inside a background `Task` with a progress indicator (export
  is synchronous and slow); on completion reveal the files in Finder (`NSWorkspace.activateFileViewerSelecting`);
  on throw, error alert.
- **Record:** present `RecordSheet` — display choice (default main display) and a duration field.
  On confirm, resolve a full-display `ResolvedTarget` via `TargetResolver` and call
  `await model.record(target:seconds:outBundle:appVersion:createdISO:)`, writing the new bundle to
  a user-chosen location, then the model reopens it. The sheet is `@available(macOS 12.3, *)`; on
  older systems Record is disabled with an explanatory tooltip. This flow is only functional on
  macOS 13+ (capture yields no frames on macOS 12.6).

## Pure helpers (the testable core of this plan)

- `enum TimelineLayout { static func xPositions(segments: [FocusSegment], duration: Seconds,
  width: CGFloat) -> [CGRect] }` — maps each segment's `[start,end]` to an x-rect within `width`
  (clamped to `[0,width]`, height left to the caller via a fixed band); empty/zero-duration →
  empty rects. Returned rects align index-for-index with `segments`.
- `enum TimeLabel { static func format(_ seconds: Double) -> String }` — `m:ss` (e.g. 63.4 →
  "1:03"); negative clamps to "0:00".

## Error handling

- Open/Save/Export/Record failures surface as SwiftUI alerts with the underlying error text; the
  app never crashes on a bad bundle (it relies on `EditorModel`'s tolerant `open`).
- Export runs off the main thread; the UI stays responsive with a progress indicator and disables
  the Export button while running.
- Record is disabled (with reason) when unavailable (pre-12.3) or when no display can be resolved.

## Packaging

Extend `Scripts/make-app.sh` to also build and wrap `shortscast-app` into
`.build/ShortsCastApp.app` (Info.plist: `CFBundleIdentifier` `com.shortscast.app`,
`CFBundleExecutable` `shortscast-app`, `CFBundlePackageType APPL`, `LSMinimumSystemVersion 12.0`),
ad-hoc signed via `codesign --force --deep --sign -`. Launch with `open .build/ShortsCastApp.app`.
On macOS 13+, granting the `.app` Screen Recording (system prompt) enables the Record flow.

## Testing & verification

This plan's automated coverage is intentionally limited to pure helpers; SwiftUI views are
verified by building and running.

- **Automated (this machine):** `TimelineLayoutTests` (segment→rect mapping, clamping, empty cases)
  and `TimeLabelTests` (formatting, negative clamp). `swift build` builds the app target.
- **Manual (this machine):** build the `.app`, launch, Open the synthetic demo bundle
  (`/tmp/shortscast-demo/demo.shortscast`), scrub the preview, select a segment and drag zoom-×,
  change format/style, Save, Export, confirm the MP4s. Exercises everything except capture.
- **Manual (macOS 13+ only):** the Record flow end-to-end, and the aesthetic review of a real
  screen recording exported.
- Execution note: because views are not unit-testable, most implementation tasks here are gated by
  "compiles + manual run," not test assertions — a different rhythm from Plans 1–4.

## Definition of done

- `shortscast-app` builds; `TimelineLayout`/`TimeLabel` unit tests pass; the full prior suite (114)
  still passes.
- `Scripts/make-app.sh` produces `ShortsCastApp.app` that launches and opens the demo bundle.
- Open → scrub preview → edit zoom/style/format → Save → Export produces correct MP4s (manually
  confirmed on this machine).
- Record is wired and availability-gated (end-to-end verification deferred to macOS 13+).
