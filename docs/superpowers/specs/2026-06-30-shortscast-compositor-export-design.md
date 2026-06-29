# ShortsCast Compositor & Export — Design Spec (Plan 3)

**Date:** 2026-06-30
**Status:** Approved design, pre-implementation
**Sub-project:** Plan 3 of 4 (Compositor & Export)
**Depends on:** `ShortsCastCore` (Plan 1) — `Director`, `CameraPath`, `VirtualCamera`, `CursorTrack`, `OutputFormat`; `ShortsCastCapture` (Plan 2) — `ProjectBundle`, `EventLog`.

## Summary

The compositor reads a `.shortscast` bundle (raw screen video + event log), runs the
already-built `Director` to obtain the camera path and cursor track, renders each frame
(auto-zoom crop, styled background, synthetic cursor + click ripples) with Core Image, and
exports an H.264 MP4 per chosen `OutputFormat` (9:16, 1:1, 4:5, 16:9) via AVFoundation.

This plan delivers a reusable render **library** (`ShortsCastRender`) plus a **command-line
harness** (`shortscast-export`) that the SwiftUI editor (Plan 4) reuses. Unlike capture,
the entire pipeline is verifiable on the macOS 12.6 dev machine: it uses AVFoundation
(`AVAssetReader`/`AVAssetWriter`) and Core Image, not ScreenCaptureKit, so it is tested
with a synthetic source video and offline bitmap pixel assertions.

## Goals & non-goals

In scope:
- Read a `.shortscast` bundle and produce one MP4 per chosen output format.
- Per-frame render: auto-zoom/pan crop (`Director.cropRect`), styled background (solid or
  linear gradient), rounded-corner + drop-shadow framing of the screen content,
  aspect-preserving padding, synthetic smoothed cursor, and animated click ripples.
- Batch export across multiple formats from one source.
- A one-line tweak to Plan 2 capture so the system cursor is NOT baked into `raw.mov`
  (`SCStreamConfiguration.showsCursor = false`), enabling the synthetic cursor.

Out of scope (later / parked):
- Wallpaper-image backgrounds (solid + gradient only in v1).
- Arrow-shaped cursor glyph (v1 uses a filled circle); webcam overlay; audio.
- GPU/Metal custom shaders (Core Image is sufficient for offline export).
- Editing UI / live preview (Plan 4).
- Manual per-segment style overrides beyond a single global `RenderStyle` (v1 uses one
  style for the whole export).

## Toolchain & platform

- Swift 5.7 (Xcode 14.2), same package. Platform floor `.macOS(.v12)`.
- AVFoundation + Core Image + CoreVideo + CoreMedia. No ScreenCaptureKit dependency in
  this plan (so it runs and verifies on macOS 12.6).

## Module layout

Two new targets:
- **`ShortsCastRender`** (library) — depends on `ShortsCastCore` and `ShortsCastCapture`.
- **`shortscast-export`** (executable) — depends on `ShortsCastRender`, `ShortsCastCore`,
  `ShortsCastCapture`.

Pure-vs-OS split (pure logic unit-tested; Core Image verified by offline bitmap reads;
AVFoundation verified with a synthetic test video):

| Unit | Kind | Testable |
|---|---|---|
| `RenderStyle` — background mode + colors, corner radius, shadow, padding fraction, cursor size/color, ripple params; `Codable`; a `.default` | pure config | ✅ |
| `FrameLayout` — `contentRect(exportSize:paddingFraction:)`: aspect-preserving, centered inset for the screen content | pure geometry | ✅ unit |
| `CursorRenderer` — `position(at:)` (interpolate `CursorTrack.samples`), `activeRipples(at:)` (select ripples in the animation window) | pure | ✅ unit |
| `FrameCompositor` — Core Image stack: background → cropped+scaled+rounded+shadowed frame → cursor + ripples → `CVPixelBuffer` | Core Image | ✅ render-to-bitmap pixel assertions |
| `VideoExporter` — `AVAssetReader` → composite → `AVAssetWriter` MP4 at `exportSize` | AVFoundation | ✅ via synthetic video |
| `ExportJob` — facade: bundle URL + formats + style → writes MP4(s) | orchestration | ✅ via synthetic video |
| `shortscast-export` main — parse flags, run `ExportJob` | executable | manual + test-video run |

## Data flow

`shortscast-export <bundle.shortscast> --format 9:16,1:1 --out <dir>`:
1. `ProjectBundle.read(bundle)` → `(eventLog, meta, rawVideoURL)`.
2. `Director(settings:).direct(log: eventLog, overrides: [])` → `DirectorResult`.
3. For each chosen `OutputFormat`, `VideoExporter.export(...)`:
   - `AVAssetReader` over `rawVideoURL`, `AVAssetReaderTrackOutput` yielding 32BGRA
     `CVPixelBuffer`s with their presentation times.
   - For a frame at time `t` (seconds from start): `crop = Director.cropRect(result, at: t,
     format: fmt, screen: eventLog.screenSize)`.
   - `FrameCompositor.composite(sourceFrame:, crop:, time: t, format: fmt, result:,
     style:)` → output `CVPixelBuffer` at `fmt.exportSize`.
   - Append to `AVAssetWriter` H.264 MP4 at `fmt.exportSize`, reusing the source PTS.
   - Output path: `<out>/<bundleBaseName>-<fmt.name-sanitized>.mp4`.

## FrameLayout (geometry)

`cropRect` already has the output format's aspect ratio (per `VirtualCamera`), and
`exportSize` has that same aspect, so the cropped region maps to the export frame with no
distortion. Padding is an aspect-preserving inset:

```
contentRect(exportSize, paddingFraction p):
    scale = 1 - 2*p           // p in [0, 0.49]
    w = exportSize.width * scale
    h = exportSize.height * scale
    origin = ((exportSize.width - w)/2, (exportSize.height - h)/2)
    -> CGRect(origin, w x h)   // centered, same aspect as exportSize
```

The crop→content mapping is a uniform scale + translate; the same transform maps the
cursor point from source pixel space into the output frame.

## FrameCompositor (Core Image)

Per frame, bottom → top, all at `exportSize`:
1. **Background:** solid `CIConstantColorGenerator`, or a vertical `CILinearGradient`
   between `style.gradientTop`/`style.gradientBottom`, cropped to `exportSize`.
2. **Screen content:** the source `CVPixelBuffer` as `CIImage`, cropped to `crop` (source
   px), transformed (scale + translate) into `FrameLayout.contentRect`, clipped by a
   rounded-rectangle mask (`style.cornerRadius`) and composited over a soft drop shadow
   (offset/blur/opacity from `style`).
3. **Cursor + ripples:** see below.
Output rendered into a pooled `CVPixelBuffer` via a shared `CIContext`.

## Cursor & ripples

- `CursorRenderer.position(at: t)` interpolates `CursorTrack.samples` (sorted by `t`):
  clamp before first / after last; linear interpolation between the bracketing samples.
  Returns a point in source pixel space, or nil if there are no samples.
- The cursor point is mapped through the crop→content transform; if it lies outside
  `crop`, the cursor is not drawn.
- Cursor glyph: filled circle, `style.cursorRadius` and `style.cursorColor`.
- `CursorRenderer.activeRipples(at: t)` returns ripples with `0 <= t - ripple.t <=
  style.rippleDuration`; each draws an expanding ring whose radius grows from
  `style.cursorRadius` to `style.rippleMaxRadius` and whose opacity fades to 0 over the
  ripple's elapsed fraction.

## Export

- Video only (no audio track in v1). H.264 via `AVAssetWriterInput` with
  `AVVideoCodecKey: .h264`, width/height = `fmt.exportSize`.
- One `AVAssetReader`/`AVAssetWriter` pass per format; batch is a loop over formats.
- Presentation timestamps copied from the source so output duration and motion match.
- Frame rate follows the source (one composited output frame per source frame).

## CLI

```
shortscast-export <bundle.shortscast>
                  --format 9:16[,1:1,4:5,16:9]
                  --out <dir>
                  [--style <path-to-RenderStyle.json>]
```
- `--format` accepts a comma-separated list matching `OutputFormat.name` values
  (`9:16`, `1:1`, `4:5`, `16:9`); at least one required.
- `--out` directory is created if missing.
- `--style` loads a `RenderStyle` JSON; omitted → `RenderStyle.default`.
- Prints each written MP4 path. Exits non-zero with a clear message on: missing/invalid
  bundle, unreadable video track, unknown format name, or zero frames rendered.

## Error handling

- Missing/unreadable bundle or `raw.mov` → clear error + non-zero exit.
- `AVAssetReader`/`AVAssetWriter` failure → surface the underlying error.
- Source video with no video track or zero frames → explicit error rather than an empty MP4.
- Unknown `--format` token → error listing valid names.

## Plan 2 tweak (folded into this plan's first task)

In `Sources/ShortsCastCapture/TargetResolver.swift`, set
`configuration.showsCursor = false` on the `SCStreamConfiguration` so the OS cursor is not
baked into `raw.mov` (the compositor draws the synthetic cursor instead). Isolated one-line
change; existing capture tests are unaffected (they don't assert on `showsCursor`).

## Testing & verification

Pure unit tests:
- `FrameLayout.contentRect` — padding inset math, centering, aspect preserved (e.g.
  1080×1920 @ p=0.05 → 972×1728 centered at (540,960)).
- `CursorRenderer.position(at:)` — clamping at ends, midpoint interpolation, nil on empty.
- `CursorRenderer.activeRipples(at:)` — inclusion window, fade fraction at boundaries.
- `RenderStyle` defaults / JSON round-trip.

Compositor tests (offline, real Core Image):
- Render one frame with a synthetic solid-color source `CIImage` + a known `RenderStyle`;
  render the output `CVPixelBuffer`/`CGImage` to a bitmap and assert sentinel pixels:
  background corner equals the configured background color; the content-rect center equals
  the source color; a pixel near a just-clicked point shows a ripple ring.

Exporter tests (offline, real AVFoundation — runs on macOS 12.6):
- `TestVideoFactory` writes a short (e.g. 1 s, 30 fps) solid-color `raw.mov` via
  `AVAssetWriter` and a matching `events.json`/`EventLog`; build a temp `.shortscast`.
- Run `ExportJob` for 9:16 and 1:1; assert each MP4 exists, has the format's exact pixel
  dimensions, and a duration/frame count matching the source (within one frame).

Manual check:
- Run `shortscast-export` on the synthetic bundle (and any real bundle once available) and
  eyeball the MP4s.

## Interfaces produced (for Plan 4)

- `ShortsCastRender`: `FrameCompositor.composite(...)`, `VideoExporter.export(...)`,
  `ExportJob.run(bundle:formats:style:outDir:)`, `RenderStyle`, `FrameLayout`,
  `CursorRenderer` — the editor reuses these for live preview (compositing a single frame)
  and final export, swapping the CLI for UI controls and per-segment style.
