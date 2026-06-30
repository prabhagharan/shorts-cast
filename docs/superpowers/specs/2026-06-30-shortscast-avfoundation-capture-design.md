# ShortsCast AVFoundation Capture — Design Spec (Plan 2b)

**Date:** 2026-06-30
**Status:** Approved design, pre-implementation
**Sub-project:** Plan 2b — replace the capture backend so live recording works on the macOS 12.6 dev machine.
**Supersedes:** the ScreenCaptureKit capture engine from Plan 2 (`ScreenCaptureSession`, the SCK parts of `TargetResolver`).

## Summary

ScreenCaptureKit (Plan 2's capture backend) starts without error but delivers **zero frames** on
macOS 12.6 (verified extensively). A spike proved that AVFoundation's **`AVCaptureScreenInput`**
captures the main display fine on this machine (2560×1600, real frames). This plan swaps the
capture **frame source** from `SCStream` to `AVCaptureScreenInput`, leaving the rest of the capture
pipeline — `CGEventTap` event recording, `EventMapper`, `EventLogBuilder` (60 Hz cursor throttle,
t=0 timestamp rebasing), `CaptureGeometry`, `ProjectBundle` — and everything downstream
(compositor, export, editor) **unchanged**. The result: live screen recording, and therefore the
full Record → edit → preview → Export loop, works on this machine without an OS upgrade.

Because `AVCaptureScreenInput` is available since macOS 10.7, the `@available(macOS 12.3, *)`
guards that SCK forced (on `Recorder`, `TargetResolver`, `ResolvedTarget`, `EditorModel.record`,
and the `shortscast-rec` CLI) are removed.

## Goals & non-goals

In scope:
- New `AVScreenCaptureSession` (AVCaptureScreenInput → AVCaptureVideoDataOutput → AVAssetWriter),
  replacing `ScreenCaptureSession`.
- Rewritten `TargetResolver` using CoreGraphics (no ScreenCaptureKit). Supports display, region
  (`AVCaptureScreenInput.cropRect`), and window (CGWindowList bounds lookup → crop to that rect).
- `ResolvedTarget` reshaped to drop SCK types.
- `Recorder` updated to use the new session; all capture `@available(macOS 12.3)` guards removed.
- `capturesCursor = false` on the screen input (replacing the deleted SCK `showsCursor = false`).
- A pure, unit-tested window-selection helper `WindowFinder.selectBounds(in:matching:)`.

Out of scope / unchanged:
- `CaptureGeometry`, `EventMapper`, `EventLogBuilder`, `EventTap`, `ProjectBundle`, the CLI option
  parser, and all of `ShortsCastCore`/`ShortsCastRender`/`ShortsCastEditor` logic stay as-is
  (apart from removing the now-unneeded `@available` on `EditorModel.record`).
- ScreenCaptureKit is removed, not kept as an alternate backend (it never worked here; YAGNI). A
  future SCK path for macOS 14+ window/region efficiency is a possible later enhancement.
- No audio, no live-preview-during-capture, no multi-display simultaneous capture.

## Toolchain & platform

- Swift 5.7 (Xcode 14.2). Package platform floor stays `.macOS(.v12)`; capture no longer has any
  runtime availability gate (`AVCaptureScreenInput` is 10.7+).
- AVFoundation, CoreMedia, CoreVideo, CoreGraphics, ApplicationServices (CGWindowList).

## AVScreenCaptureSession

Mirrors the old `ScreenCaptureSession`'s writer/anchor logic, sourced from AVCapture:

- `init(outputURL: URL, displayID: CGDirectDisplayID, cropRect: CGRect?, pixelSize: CGSize)`.
- Builds `AVCaptureSession` + `AVCaptureScreenInput(displayID:)`:
  - `capturesCursor = false`
  - `minFrameDuration = CMTime(value: 1, timescale: 60)`
  - `cropRect = cropRect` when non-nil (region/window); unset for full display.
- `AVCaptureVideoDataOutput` (pixel format 32BGRA) with a sample delegate on a serial queue.
- `start() async throws`: configure session + `AVAssetWriter` (H.264 at `pixelSize`), `startRunning()`.
- Sample delegate `captureOutput(_:didOutput:from:)`:
  - First valid frame: `writer.startWriting()`, `startSession(atSourceTime: pts)`,
    `firstFramePTSSeconds = CMTimeGetSeconds(pts)`.
  - Append the frame's `CVPixelBuffer` at its PTS while `writer.status == .writing` and the input
    `isReadyForMoreMediaData`.
- `stop() async -> (firstFrameT: Double, endT: Double)`: stop the session, drain the sample queue,
  `markAsFinished` + `finishWriting` (only if started), capture `writerError`, return
  `(firstFramePTSSeconds ?? endT, endT)`. Same robustness (queue drain, writer-failure surfacing,
  no-frames handling) the exporter/SCK code already established.

**Clock sync (preserved):** `AVCaptureVideoDataOutput` PTS is on the host-time clock
(`CMClockGetHostTimeClock`, mach-based) — the same timeline as the event tap's `machNowSeconds()`.
So `firstFramePTSSeconds` and event timestamps share an epoch and `EventLogBuilder.build` rebases
events to t=0 exactly as under SCK. No event-sync changes.

No CoreImage crop is needed in capture: `cropRect` produces already-cropped frames, so the writer's
output size equals the captured area's pixels.

## TargetResolver (CoreGraphics)

`resolve(displayIndex: Int?, windowQuery: String?, region: CGRect?) -> ResolvedTarget` is
**synchronous** (no async `SCShareableContent`).

`ResolvedTarget`:
```
struct ResolvedTarget {
    let kind: String                 // "display" | "region" | "window"
    let displayID: CGDirectDisplayID
    let captureRectPoints: CGRect    // captured area in global points (events map into this)
    let scale: CGFloat               // pixels per point
    let cropRect: CGRect?            // AVCaptureScreenInput.cropRect (display-local); nil = full display
}
```

Resolution:
- **Display:** `displayIndex` selects from `CGGetActiveDisplayList` (default `CGMainDisplayID()`).
  `captureRectPoints = CGDisplayBounds(id)`; `scale = CGDisplayCopyDisplayMode(id).pixelWidth /
  bounds.width`; `cropRect = nil`.
- **Region:** `captureRectPoints = region` (clamped to its display's bounds); `scale` = that
  display's scale; `cropRect` = the region in the display-local coordinate space.
- **Window:** `CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)` →
  `WindowFinder.selectBounds(in:matching: windowQuery)` returns the matched window's
  `kCGWindowBounds`; pick the display containing it; `captureRectPoints` = those bounds;
  `cropRect` = bounds in display-local coords. Window bounds are captured once at resolve time
  (the window-doesn't-move limitation, unchanged from Plan 2).

`Recorder` builds `CaptureGeometry(captureRect: captureRectPoints, scale: scale)` exactly as before,
so `EventLog.screenSize = geometry.pixelSize = captureRectPoints × scale`. Out-of-bounds events are
dropped by `CaptureGeometry` as before.

**Verification note:** `AVCaptureScreenInput.cropRect`'s exact unit/origin convention is confirmed
during the manual run so a region/window crop's output pixels line up with
`captureRectPoints × scale`. Full-display is already spike-confirmed.

## WindowFinder (pure, tested)

```
enum WindowFinder {
    static func selectBounds(in windows: [[String: Any]], matching query: String) -> CGRect?
}
```
- Iterates the CGWindowList-shaped dictionaries; matches when the window's owner name
  (`kCGWindowOwnerName`) case-insensitively contains `query`, or the window number
  (`kCGWindowNumber`) equals `query`; returns the first match's `kCGWindowBounds` as a `CGRect`
  (built from the bounds dict's X/Y/Width/Height). Returns nil if none match or bounds are missing.
- Unit-tested with synthetic dictionaries (the live `CGWindowListCopyWindowInfo` call is the only
  OS-bound part and is exercised by the manual run).

## Recorder & ripple changes

- `Recorder.record(target:seconds:outBundle:appVersion:createdISO:)`: same flow (geometry →
  EventLogBuilder → EventTap → capture session → stop → build EventLog → ProjectBundle.write),
  swapping `ScreenCaptureSession` for `AVScreenCaptureSession` and removing `@available`.
- Remove `@available(macOS 12.3, *)` from `EditorModel.record` (ShortsCastEditor).
- `shortscast-rec` main: remove both `#available(macOS 12.3)` guards (top-level and inside the
  `Task`); keep the existing `Task { … exit }` + `CFRunLoopRun()` structure (harmless and already
  working).
- Delete `ScreenCaptureSession.swift`; delete the SCK content-filter/config code in
  `TargetResolver`.

## Error handling

- No display / no matching window / bad region → clear thrown error before capture starts.
- `AVCaptureScreenInput(displayID:)` returning nil, or session can't add input/output → thrown error.
- Writer failure / zero frames captured → surfaced (same handling as the existing pipeline);
  partial output cleaned up.

## Testing & verification

- **Automated (this machine):** `WindowFinderTests` (owner-name match, window-number match, no
  match, missing bounds → nil). The unchanged pure capture suite (CaptureGeometry, EventMapper,
  EventLogBuilder, ProjectBundle) still passes. `swift build` builds all targets.
- **Manual (this machine — the payoff):**
  - `shortscast-rec --seconds 5 --out /tmp/t.shortscast --direct` → click/type during capture →
    confirm a playable `raw.mov`, `events.json` with clicks at plausible pixel coords, and non-zero
    `--direct` Director segments/keyframes.
  - Region: `--rect x,y,w,h` → confirm the cropped area is captured and events inside it appear.
  - Window: `--window <app-name>` → confirm the window's region is captured.
- **OS-bound, verified by the above run:** `AVScreenCaptureSession` and the live `TargetResolver`
  display/window resolution.

## Definition of done

- `AVScreenCaptureSession` + rewritten `TargetResolver` build; `WindowFinder` unit tests pass; the
  full prior suite still passes; ScreenCaptureKit is removed.
- `@available(macOS 12.3)` guards removed across capture, `EditorModel.record`, and the CLI.
- Manual run on this Mac records a real `.shortscast` (full display at minimum; region/window
  confirmed), and `--direct` shows the captured events drive the Director.

## Ripple into Plan 5

Plan 5's `RecordSheet`/Record button no longer need the macOS-12.3 availability gate (capture is
now unconditional on macOS 12). The Plan 5 plan/spec will be updated accordingly when executed; if
Plan 2b lands first, the Record flow is fully verifiable on this machine.
