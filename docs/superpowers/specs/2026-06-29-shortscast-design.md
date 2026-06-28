# ShortsCast — Design Spec

**Date:** 2026-06-29
**Status:** Approved design, pre-implementation
**Working name:** ShortsCast

## Summary

A macOS-native app for recording the screen/windows and turning the recording into
polished short-form tutorial videos. The two headline features are:

1. **Auto-zoom** driven by mouse clicks (and typing, scrolling, cursor dwell), with
   user-controllable zoom magnitude.
2. **Format fitting** that reframes one recording into multiple social formats
   (9:16, 1:1, 4:5, 16:9) by auto-panning a virtual camera to follow the action.

The product follows a **record → auto-direct → edit → export** pipeline. Capture is
lossless and "dumb" (raw screen video + event metadata); all visual effects (zoom,
pan, background, cursor) are **non-destructive compositing** driven by an editable
camera path. Nothing is baked until export, so a single recording can be re-exported
to every format.

## Platform & tech stack

- **macOS native**, Swift + SwiftUI.
- **ScreenCaptureKit** — screen/window capture (high-res, 60fps, H.264/HEVC `.mov`).
- **Core Image / Metal** — per-frame GPU compositing (camera transform, background, cursor).
- **AVFoundation (`AVAssetWriter`)** — offline export rendering.
- **CGEventTap** (Accessibility) — global mouse/keyboard/scroll event capture.

## v1 scope

In scope: auto-zoom, multi-format fitting, styled background, cursor polish.

Parked for later: **webcam overlay**, **audio capture** (mic/system audio).

## Architecture

Seven focused components:

| Component | Responsibility |
|---|---|
| **Capture Engine** | Records raw screen video via ScreenCaptureKit |
| **Event Recorder** | Timestamps mouse clicks, key-presses, scrolls, and cursor positions |
| **Project Store** | Bundles raw video + event log + user edits as a saveable project |
| **Auto-Director** | Pure function: event log → smooth virtual-camera path (zoom + pan keyframes) + scene segments |
| **Compositor** | Per-frame GPU render: camera transform, styled background, cursor polish |
| **Editor UI** | Live preview + timeline of zoom segments + format/background controls + manual keyframe tweaks |
| **Exporter** | Renders composited frames to MP4 per chosen format |

Design principle: capture is lossless and minimal; all "magic" is non-destructive and
re-editable. This keeps each unit independently testable and lets one source produce
every output format.

## 1. Capture Engine

- Records the selected display/window via ScreenCaptureKit to a high-resolution,
  60fps `.mov` (H.264 or HEVC).
- Excludes the system cursor from the capture (cursor is re-drawn at composite time —
  see Cursor Polish).
- Writes the raw video into the project bundle.

## 2. Event Recorder

Captures a time-ordered **event log** during recording, with timestamps relative to
recording start:

- Mouse clicks `{t, x, y, button}`
- Key-press events `{t}` — **occurrence and time only; never which keys** (not a keylogger)
- Scroll events `{t, x, y, delta}`
- Periodic cursor position samples `{t, x, y}`

Persisted as `events.json`.

**Privacy:** keyboard capture records only that a key was pressed and when, for the
typing trigger. No keystroke content is ever logged.

## 3. Auto-Director (auto-zoom)

A **pure, deterministic function**: same event log always produces the same camera
path. Output is a timeline of `(centerX, centerY, scale)` keyframes plus scene
segments.

Algorithm:

1. **Cluster events in time + space.** Events within ~1.5s and a small screen radius
   merge into one **focus segment** (prevents jitter — rapid clicks become one steady
   zoom, not five lurches).
2. **Assign a target per segment:** center = weighted centroid of the segment's events;
   scale = based on activity density (tight clusters → tighter zoom), defaulting to the
   global zoom setting and capped at the configured max.
3. **Insert zoom-out gaps.** After ~1.5s of inactivity, or when the next segment is far
   away, ease the camera back to a wide resting scale.
4. **Smooth the path.** Run keyframes through a critically-damped spring / spline for
   fluid ease-in-out motion (never linear/snappy).
5. **Trigger weighting:** clicks = strong pull, typing = medium (zoom to active text
   region), scroll = follow vertically, dwell = gentle zoom. All tunable.

### User-controllable zoom

- **Global default zoom** (e.g. 2.5×) and a **max-zoom cap** in settings — drive
  generated keyframes.
- **Per-segment override** in the editor: select any zoom segment and set its exact
  zoom factor via slider/numeric field. Manual overrides persist even if the path is
  regenerated.

All generated keyframes are editable: drag, retime, change zoom level, or delete.

## 4. Virtual camera & format fitting

The **virtual camera** is a moving rectangle over the raw recording whose aspect ratio
equals the chosen output format. The Compositor crops to it each frame, scales to the
export resolution, and draws it on the styled background.

- **Format and zoom share one camera.** For a 9:16 export from a 16:9 screen, the
  camera is a tall rectangle that cannot show full width, so it **auto-pans to follow
  the action** (the Auto-Director's focus segments). Wide screen becomes tall video by
  following where work happens.
- **Resting framing per format:** for 9:16, the resting (un-zoomed) camera shows a
  readable tall slice centered on recent activity (not the whole shrunk screen). For
  16:9, resting = full screen.
- **Switch format anytime** from a dropdown; the camera path re-derives for the new
  aspect ratio and re-renders the preview instantly. One recording → all four formats.
- **Background layer:** behind the camera crop sits the styled background
  (wallpaper/gradient/solid); the screen content is shown with rounded corners, drop
  shadow, and configurable padding.
- **Safe-area guides:** optional overlays marking where platform UI (Shorts/Reels
  captions, buttons) covers the frame.

Supported formats (v1): **9:16** (Stories/Reels/Shorts/TikTok), **1:1** (square feed),
**4:5** (portrait feed), **16:9** (landscape).

## 5. Cursor polish

The cursor is **re-drawn at composite time** from the position samples, enabling:

- **Smoothing** — positions run through the same spring filter, removing jitter.
- **Size** — configurable enlargement for phone-screen visibility.
- **Click ripples** — animated highlight/ring on each click event.
- **Auto-hide** after inactivity (optional).

## 6. Editor UI (SwiftUI)

- **Preview canvas** — live composited playback at the selected format.
- **Timeline** — recording with zoom segments as draggable blocks; select to edit zoom
  ×, center, and timing; add/delete segments manually.
- **Inspector panel** — format dropdown, global zoom default + max cap, background
  picker, padding/corner/shadow, cursor settings, safe-area toggle.
- **Transport** — play/pause/scrub.

## 7. Export

`AVAssetWriter` renders each frame through the Compositor offline (independent of
realtime, full quality) to MP4/H.264 (or HEVC) at the format's standard resolution
(e.g. 1080×1920 for 9:16). Includes a progress bar and batch export of multiple formats.

## Data model & permissions

**Project bundle** (`.shortscast` folder):

- `raw.mov` — lossless screen capture
- `events.json` — timestamped events + cursor samples
- `project.json` — camera path, per-segment overrides, selected format, style settings

Non-destructive and re-editable indefinitely.

**Permissions:**

- **Screen Recording** — capture.
- **Accessibility** — global mouse/keyboard/scroll event tap.

Both requested with clear first-run explanations.

## Testing strategy

- **Auto-Director** and **camera-path math** are pure functions → unit-tested with
  synthetic event logs (no UI or capture needed). Primary correctness surface.
- **Compositor** verified with golden-frame snapshot tests.
- **Capture & permissions** covered by lightweight integration checks.

## Future work (out of v1 scope)

- Webcam overlay (circular/rounded bubble composited in a corner).
- Audio capture (microphone and/or system audio).
