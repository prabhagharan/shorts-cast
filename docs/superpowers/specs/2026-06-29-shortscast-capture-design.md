# ShortsCast Capture & Event Recorder — Design Spec (Plan 2)

**Date:** 2026-06-29
**Status:** Approved design, pre-implementation
**Sub-project:** Plan 2 of 4 (Capture & Event Recorder)
**Depends on:** `ShortsCastCore` (Plan 1, complete) — produces the `EventLog` that `Director.direct(log:overrides:)` consumes.

## Summary

The capture layer records a raw screen video via **ScreenCaptureKit** and a synchronized
**event log** (clicks, key-presses, scroll, cursor samples) via **CGEventTap**, and writes
both into a saveable `.shortscast` project bundle. Its output `EventLog` is exactly the
type the already-built core engine consumes, so a captured recording can be run straight
through the `Director`.

This plan delivers a reusable capture **library** plus a **command-line harness** to drive
and verify it; the SwiftUI editor app (Plan 4) reuses the same library.

## Goals & non-goals

In scope:
- Record one capture target — **full display**, **single window**, or **region** — to an
  H.264 `.mov`.
- Record a synchronized `EventLog`: mouse clicks, key-presses (time only, no keycodes),
  scroll, and cursor position samples, all in the captured area's pixel space (origin
  top-left), timestamps rebased so t=0 is the first video frame.
- Write/read a `.shortscast` project bundle.
- A CLI harness (`shortscast-rec`) that requests permissions, records for N seconds, and
  writes a bundle; with an optional `--direct` end-to-end smoke test through the core.

Out of scope (later plans / parked):
- SwiftUI editor UI (Plan 4).
- Compositor / export (Plan 3).
- Audio capture (microphone/system) — parked in the original design spec.
- Live window-move tracking (window capture uses the window rect captured at start).
- Interactive on-screen region/window pickers (region/window chosen via CLI flags here).

## Toolchain & platform constraint

- Swift 5.7 (Xcode 14.2), same package as `ShortsCastCore`.
- Package platform floor stays `.macOS(.v12)`. ScreenCaptureKit code is guarded with
  `@available(macOS 12.3, *)`; it runs on the dev machine (macOS 12.6) and all newer macOS.
  The CLI prints a clear error and exits if run on macOS < 12.3.

## Module layout

Two new targets in the existing package:

- **`ShortsCastCapture`** (library) — the reusable capture engine.
- **`shortscast-rec`** (executable) — the thin CLI harness; depends on `ShortsCastCapture`
  and `ShortsCastCore`.

Design principle: capture is OS-bound and hard to unit-test, so **pure logic is split from
OS bindings**. The interesting logic is pure and unit-tested; the OS layers are thin
adapters verified by running the CLI.

| Unit | Kind | Testable |
|---|---|---|
| `CaptureTarget` — enum: `.display(id)`, `.window(rect)`, `.region(rect)` + resolved geometry inputs | pure | ✅ |
| `CaptureGeometry` — maps global event points → captured-area pixel space (top-left); reports output pixel size | pure | ✅ unit |
| `EventMapper` — `CGEvent` (type, location, flags, scroll delta) → `RecordingEvent` | pure | ✅ unit |
| `EventLogBuilder` — accumulates events + cursor samples, rebases to t=0, throttles cursor to 60 Hz, emits `EventLog` | pure | ✅ unit |
| `ProjectBundle` — read/write the `.shortscast` folder | filesystem | ✅ unit (temp dir) |
| `ScreenCaptureSession` — `SCStream` → H.264 `.mov` via `AVAssetWriter` | OS binding | manual run |
| `EventTap` — `CGEventTap` run-loop source → feeds `EventLogBuilder` | OS binding | manual run |
| `Permissions` — check Screen Recording + Accessibility | OS binding | manual run |
| `shortscast-rec` main — parse flags, wire, record, write bundle | executable | manual run |

## Coordinate model & event mapping

The core engine expects event points in the **captured area's pixel space, origin
top-left**, and `EventLog.screenSize` = that area's pixel dimensions. The OS provides two
other spaces, so `CaptureGeometry` converts:

- **CGEvent locations** are in global display points (origin top-left of the main display,
  in points).
- **ScreenCaptureKit** frames are in pixels (points × backing scale) of the captured content.

`CaptureGeometry` holds: the capture rect in global points (`originX, originY, width,
height`), the backing `scale`, and derives output pixel size (`width*scale`,
`height*scale`). For each event point it: (1) subtracts the capture rect origin, (2)
multiplies by `scale` → pixels, (3) yields a point in `[0, pixelWidth] × [0, pixelHeight]`.

Per target:
- **Full display:** capture rect = the display's global frame (origin from its arrangement
  position); `scale` = the display's backing scale factor.
- **Window:** capture rect = the window's frame captured once at session start (fixed for
  the recording; moving the window mid-recording is a documented limitation).
- **Region:** capture rect = the `--rect x,y,w,h` global-point rectangle the user passed.

**Out-of-bounds handling:** click, scroll, and cursor events whose mapped point falls
outside `[0, pixelWidth] × [0, pixelHeight]` are **dropped** (they would zoom content that
isn't in frame). Key events carry no location and are always kept.

## Capture pipeline (`ScreenCaptureSession`)

An `SCStream` configured from an `SCContentFilter`:
- display → filter for that display,
- window → filter scoped to the one window,
- region → display filter, capturing the whole display; each frame is then cropped to the
  region via CoreImage (`SCStreamConfiguration.sourceRect` is macOS 14+, but the dev machine
  is 12.6, so cropping is done ourselves).

Frames arrive as `CMSampleBuffer`s on an `SCStreamOutput` callback and are appended to an
`AVAssetWriter` configured for H.264, 60 fps cap, native pixel size, `.mov`. The writer
session starts on the first frame (anchoring t=0) and is finalized on stop. All
ScreenCaptureKit usage is under `@available(macOS 12.3, *)`.

## Event recorder (`EventTap`) & shared clock

A listen-only `CGEventTap` on a dedicated run loop captures: left/right/other mouse-down,
scroll wheel, key-down, and mouse-moved (cursor). One monotonic clock
(`mach_absolute_time` via `CMClock`/`CMTime`) timestamps both the first video frame and
every event; `EventLogBuilder` rebases everything so t=0 is the first frame.

- Cursor moves are **throttled to 60 Hz** in the builder (keep the latest sample per ~16 ms
  tick), not recorded raw.
- Key events record **time only — no keycodes/characters** (privacy guarantee preserved
  end-to-end).
- Mouse buttons map: left → `.left`, right → `.right`, others → `.other`.
- Scroll `deltaY` is taken from the wheel event and recorded as-is (sign preserved).

## Project bundle & CLI

`ProjectBundle` writes/reads a `.shortscast` folder:
- `raw.mov` — the recording
- `events.json` — the `EventLog` (Codable, defined in core)
- `meta.json` — capture target, display id, backing scale, app/version, created date
  (date passed in by the caller; not read from a wall clock inside pure code)

CLI:
```
shortscast-rec --seconds N
               [--display N | --window <app-name-or-id> | --rect x,y,w,h]
               --out path.shortscast
               [--direct]
```
Behavior: check permissions (exit non-zero with guidance if missing); record for N seconds
(fixed duration; interactive stop is deferred to the editor in Plan 4); write the bundle;
print the output path. With `--direct`, run the
captured `EventLog` through `ShortsCastCore`'s `Director` and print the generated
segment/keyframe counts — an end-to-end smoke test.

## Permissions

`Permissions` checks:
- Screen Recording via `CGPreflightScreenCaptureAccess()` (and may call
  `CGRequestScreenCaptureAccess()`).
- Accessibility via `AXIsProcessTrusted()`.

If either is missing, the CLI prints exactly which permission to enable in System Settings
and exits non-zero, rather than failing cryptically mid-capture.

## Error handling

- Missing permission → clear message + non-zero exit before any capture starts.
- macOS < 12.3 → clear message + non-zero exit.
- No matching display/window for the requested target → error + exit.
- `AVAssetWriter` failure → surface the error, finalize/clean up partial file.
- Empty recording (no frames) → error rather than writing a zero-duration bundle.

## Testing & verification

Unit-tested (pure):
- `CaptureGeometry` — all three targets, Retina (2×) scaling, out-of-bounds drop, origin
  offset on a non-main display.
- `EventMapper` — each CGEvent type → correct `RecordingEvent`; button mapping; scroll
  delta sign; key events carry no location.
- `EventLogBuilder` — rebasing so first event/frame is t=0; 60 Hz cursor throttle keeps the
  latest per tick; events emitted sorted by time; out-of-bounds drop applied via geometry.
- `ProjectBundle` — write then read round-trip in a temp directory reproduces the `EventLog`
  and meta.

Manual verification (OS-bound, on this Mac):
- Run `shortscast-rec --seconds 5 --direct --out /tmp/test.shortscast`.
- Confirm `raw.mov` plays, `events.json` has clicks at plausible pixel coordinates, and the
  `--direct` output reports non-zero Director segments/keyframes.
- The implementation plan includes this manual checklist as its final task.

## Interfaces produced (for Plan 3 / Plan 4)

- `ShortsCastCapture` library with `ScreenCaptureSession`, `EventTap`, `ProjectBundle`,
  `CaptureGeometry`, `CaptureTarget`, and a top-level `Recorder` facade that ties capture +
  events together and returns/writes a bundle.
- The `.shortscast` bundle format (raw.mov + events.json + meta.json), read back via
  `ProjectBundle`, which the editor (Plan 4) and compositor/export (Plan 3) consume.
