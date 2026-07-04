# ShortsCast — System Design

**Status:** Living document · **Last updated:** 2026-07-05

This is the architecture reference and design record for ShortsCast as a whole. It
explains how the system is structured *and* why — the decisions and trade-offs behind the
structure are collected in [§7](#7-design-decisions--trade-offs). Per-subsystem detail
stays at the module level; the [Core engine](#4-core-engine-the-auto-zoom) is documented
deeper because it is the part a reader cannot reconstruct from the code's obvious shape.

For usage, see the [README](../../../README.md). For the MCP agent surface in full, see
[`2026-07-01-shortscast-mcp-agent-design.md`](./2026-07-01-shortscast-mcp-agent-design.md).

---

## 1. Overview & goals

ShortsCast is a macOS-native screen recorder that turns a plain screen recording into a
polished short-form video automatically. Its two headline capabilities:

- **Click-driven auto-zoom** — the camera zooms and pans to follow what you're doing,
  derived from the clicks / keystrokes / scrolls captured during recording.
- **Multi-format fitting** — one recording exports to 9:16, 1:1, 4:5, or 16:9, each via an
  auto-panning virtual camera that keeps the action in frame.

**Constraints that shaped everything:**

- **macOS 12 (Monterey) or later.** The dev/target machine runs Monterey, which forces two
  choices below: AVFoundation for capture, and a hand-rolled MCP server.
- **Swift 5.7, zero external dependencies.** The whole system is one SwiftPM package.
- **Native.** SwiftUI GUI, AVFoundation capture, Core Image compositing, AVFoundation export.

**Design philosophy — pure core, side-effecting shells.** All the interesting logic (the
auto-zoom math) lives in a pure, deterministic core with no I/O. Capture, rendering, and
the control surfaces are thin shells around it. This is what makes the system testable
(§8) and what keeps the invention isolated from platform quirks.

---

## 2. Architecture at a glance

Five layers. Dependencies point strictly **inward** — the core knows nothing about
capture, files, or the agent; each outer layer depends only on those inside it.

```
                        ┌───────────────────────────────────────────┐
   control surfaces →   │  shortscast-rec   shortscast-export        │
                        │  shortscast-app (GUI)   shortscast-mcp      │
                        └───────────────┬───────────────────────────┘
                                        │ depends on
        ┌───────────────────────────────┴───────────────────────────┐
        │  ShortsCastEditor   headless open→direct→edit→preview→export │
        └───────────────┬────────────────────────────┬───────────────┘
                        │                            │
        ┌───────────────┴──────────┐   ┌─────────────┴──────────────┐
        │  ShortsCastRender        │   │  ShortsCastCapture         │
        │  Core Image compositor   │   │  frame + input capture,    │
        │  + H.264 exporter        │   │  target resolution, bundle │
        └───────────────┬──────────┘   └─────────────┬──────────────┘
                        │                            │
                        └──────────────┬─────────────┘
                                       │
                        ┌──────────────┴──────────────┐
                        │  ShortsCastCore              │
                        │  pure engine — no I/O        │
                        └──────────────────────────────┘
```

**Libraries:** `ShortsCastCore`, `ShortsCastCapture`, `ShortsCastRender`,
`ShortsCastEditor`, `ShortsCastMCP`.
**Executables:** `shortscast-rec` (CLI record), `shortscast-export` (CLI export),
`shortscast-app` (SwiftUI GUI), `shortscast-mcp` (MCP agent server).

The dependency arrows are the contract: you can change how the compositor draws a shadow
without touching the core, and you can unit-test the core without a screen. `Render` and
`Editor` depend on `Capture` only for the shared bundle-I/O and model types, not for live
capture.

---

## 3. The `.shortscast` bundle

The bundle is the on-disk contract every layer speaks. A recording is a directory (a
"bundle") named by UTC timestamp, e.g. `2026-07-05_131820.shortscast/`, containing:

| File | Written by | Contents |
|------|-----------|----------|
| the raw video | Capture | the unmodified screen capture (`.mov`) |
| `events.json` | Capture | the `EventLog`: every recorded click/key/scroll/cursor sample with timestamps, plus screen size and duration |
| `meta` | Capture | `BundleMeta`: target kind, display id, capture rect, scale, app version, created timestamp |
| `project.json` | Editor / MCP | `ProjectEdits`: per-segment camera overrides, render style, chosen format, and director settings |

**Why this matters:** `events.json` is the raw material the Core engine re-directs on
demand — directing is deterministic, so segments are never persisted, only recomputed.
`project.json` holds *edits* layered on top. Because every control surface (CLI, GUI, MCP)
reads and writes the same `project.json`, they all agree on the same state: an agent can
adjust a segment, and the GUI opening that bundle sees the change. `ProjectBundle`
(in Capture) is the read/write gateway; `EditsStore` (in MCP) is the thin
`project.json` accessor.

---

## 4. Core engine — the auto-zoom

`ShortsCastCore` is pure and deterministic: same `EventLog` + same settings → same camera
path, byte for byte. No files, no clock, no capture. Everything else is built on it.

### Entry point — `Director`

`Director.direct(log:overrides:)` is the single orchestration point. Given an `EventLog`
and optional manual overrides it produces a `DirectorResult` (segments + camera path +
cursor track) in five steps:

```
EventClusterer  ─┐
                 ├─ mergeNonOverlapping ─ applyOverrides ─ AutoDirector.cameraPath
DwellDetector   ─┘                                          + CursorTrackBuilder
```

### Step 1 — clustering events into focus segments (`EventClusterer`)

Triggering events (everything except raw cursor motion) are sorted by time and grouped
greedily. An event joins the current cluster if it is **within time** (`clusterTimeGap`,
default 1.5 s since the last event) **and within space** (within `clusterRadius`,
default 300 px, of the cluster's running weighted centroid). Otherwise the cluster is
flushed and a new one starts.

Each flushed cluster becomes a `FocusSegment` spanning its first-to-last event time,
centered on its **weighted centroid** — clicks weigh more than keys weigh more than scrolls
(`clickWeight` 1.0, `keyWeight` 0.6, `scrollWeight` 0.5), so the camera favors where you
clicked. Zoom is `defaultZoom` (2.5), plus a `denseZoomBonus` (0.5) when a cluster has at
least `denseEventCount` (5) events — dense activity zooms in tighter — clamped to `maxZoom`
(4.0).

### Step 2 — dwell segments (`DwellDetector`)

A secondary pass emits gentle-zoom segments where the **cursor lingers** — sits within
`dwellRadius` (60 px) for at least `dwellTime` (1.0 s) — even with no clicks. These are
merged with the click clusters, non-overlapping, so a pause-and-read still gets a modest
zoom (`dwellZoom` 1.6) without fighting the click-driven segments.

### Step 3 — the eased camera path (`AutoDirector`)

`AutoDirector.cameraPath` turns the ordered segments into a keyframed `CameraPath`. It
starts at a resting state (`restingZoom` 1.0, centered on `restingAnchor`). For each
segment it pushes keyframes: hold → **ease in** over `zoomInDuration` → hold while active.
Then the key rule:

> Return to resting only if there is room to complete the zoom-out before the next segment
> begins (`gap > inactivityTimeout + zoomOutDuration`). Otherwise stay zoomed and let the
> next segment pan directly from the current position.

This avoids a distracting zoom-out/zoom-in flicker between rapid-fire segments. Zoom-out
either pulls back to the resting anchor or stays in place (`zoomOutInPlace`). Per-segment
`zoomInDuration`/`zoomOutDuration` overrides beat the global defaults.

### Step 4 — fitting to a format (`VirtualCamera`)

The camera path is format-agnostic — it works in screen space. `VirtualCamera.cropRect`
maps a sampled `CameraState` (center + scale) to a crop rectangle for a given
`OutputFormat`. It computes the largest rect of the target aspect ratio that fits the
screen (`baseCropSize`), divides by the zoom scale, and **clamps the crop inside the screen
bounds** so panning never runs off the edge. This is how one recording yields 9:16 and
16:9 from the same path: only the base crop aspect differs.

### Step 5 — cursor smoothing (`SpringSmoother`)

Raw cursor samples are jittery. `SpringSmoother` runs them through a **critically-damped
spring** (`x'' = ω²(target − x) − 2ω·x'`, semi-implicit Euler) so the synthetic cursor
glides. It substeps the integration when input `dt` is large, keeping the integrator stable
at any sample rate. `CursorTrackBuilder` wraps this into the `CursorTrack` the compositor
draws.

### Editability is a first-class input

`SegmentOverride` + `applyOverrides` let any surface replace a segment's zoom / center /
easing by index before the path is built. This is the seam the Editor and the MCP
`set_segment_camera` tool write through — the auto decisions are defaults, not verdicts.

---

## 5. Capture, Render, Editor

### ShortsCastCapture

**Responsibility:** produce a `.shortscast` bundle from a live screen + input capture.
**Key pieces:** `AVScreenCaptureSession` (frames via `AVCaptureScreenInput`), a CGEventTap
recorder (clicks/keys/scrolls/cursor → `EventLog`), `TargetResolver` (resolves a display
index / window query / region to a `CGDirectDisplayID` + crop rect using CoreGraphics),
`RecordingController` (orchestrates a recording), `Permissions` (Screen Recording +
Accessibility + Input Monitoring), and `ProjectBundle` (bundle read/write).
**Decisions:** AVFoundation over ScreenCaptureKit (§7.1); the synthetic cursor is drawn at
render time, so capture sets `showsCursor=false` to avoid a doubled cursor.

### ShortsCastRender

**Responsibility:** composite and export. **Key pieces:** a Core Image compositor that per
frame crops to the virtual-camera rect, draws the framed screen (rounded corners, drop
shadow) on a solid/gradient background, and overlays the synthetic cursor with click
ripples; an AVFoundation exporter that writes H.264 MP4 per `OutputFormat`; and `ExportJob`,
which ties bundle → `Director` → compositor → exporter into one call honoring saved edits.
**Verification:** offline bitmap pixel assertions and a two-tone-source test that guards
against vertical flips (§8).

### ShortsCastEditor

**Responsibility:** a headless editor model (`EditorModel`, an `ObservableObject`) that the
GUI binds to. **Flow:** open a bundle → run `Director` → hold edits (per-segment overrides,
style, format, settings) → live-preview a frame via an injectable `FrameSource` → persist
edits to `project.json` → export honoring overrides. It is deliberately UI-free so it can
be tested without SwiftUI, and so the GUI is a thin binding layer.

---

## 6. Control surfaces

All four surfaces are thin shells over the libraries above; none contain engine logic.

- **`shortscast-rec`** — `--seconds N --out bundle [--display N | --window <app-or-id> |
  --rect x,y,w,h] [--direct]`. Records and optionally auto-directs.
- **`shortscast-export`** — `<bundle> --format 9:16[,1:1,4:5,16:9] --out <dir>
  [--style <json>]`. Exports one or more formats from a bundle.
- **`shortscast-app`** — SwiftUI GUI owning an `EditorModel`: toolbar (Open/Save/Record/
  Export) + preview + inspector + timeline. The only logic-bearing UI code is a couple of
  pure, unit-tested layout helpers.
- **`shortscast-mcp`** — the MCP agent server. Newline-delimited JSON-RPC 2.0 over stdio
  (`initialize` / `tools/list` / `tools/call`), exposing **12 tools** (start/stop/status,
  list_recordings/displays/windows/segments, set_segment_camera/director_settings/style,
  export_recording, open_in_app). It is a **pure control surface** — every handler wraps an
  existing library call, injects its side-effecting collaborators for testability, and
  persists camera/tuning edits to `project.json` so all surfaces stay in sync. Full design:
  the [MCP agent spec](./2026-07-01-shortscast-mcp-agent-design.md).

---

## 7. Design decisions & trade-offs

The consolidated "why." Each: the decision, its context, and its consequence.

### 7.1 AVFoundation for capture, not ScreenCaptureKit

**Context:** ScreenCaptureKit is Apple's modern capture API, but on macOS 12 (Monterey) it
delivers **zero frames** — even from a signed app. **Decision:** capture frames with
AVFoundation's `AVCaptureScreenInput` and resolve targets with CoreGraphics
(`CGDisplayBounds`, `CGWindowList`). **Consequence:** works on Monterey; keeps the platform
floor at `.macOS(.v12)`; removes all `@available(12.3)` gating. Trade-off: a slightly
lower-level capture path and manual coordinate/crop handling.

### 7.2 Hand-rolled MCP server, not the official Swift SDK

**Context:** the MCP Swift SDK requires macOS 13 / Swift 6.1, which would drop Monterey
support and not run on the target machine. **Decision:** hand-roll a minimal JSON-RPC 2.0
stdio server (only `initialize` / `tools/list` / `tools/call` are needed for a tools-only
server). **Consequence:** stays on Swift 5.7 / `.v12` with zero dependencies. Trade-off: we
own ~a few hundred lines of protocol plumbing instead of importing it.

### 7.3 Pure deterministic core, side-effecting shells

**Context:** the auto-zoom math is the invention and the thing most worth testing.
**Decision:** isolate it in `ShortsCastCore` with no I/O; push all side effects to outer
layers behind injectable interfaces. **Consequence:** the core is exhaustively unit-tested
without a screen; the shells are tested with fakes (§8); directing is reproducible.

### 7.4 Post-hoc, index-keyed camera edits persisted to the bundle

**Context:** users and agents need to override auto decisions and have every surface agree.
**Decision:** edits are `SegmentOverride`s applied at direct time, persisted in
`project.json`; segments themselves are never persisted (they're recomputed). **Consequence:**
CLI, GUI, and MCP share one source of truth. Trade-off — **index drift:** because overrides
are keyed by segment index, any *resegmenting* settings change can shift what an index
refers to. The MCP layer mitigates this by classifying settings changes as safe vs
resegmenting and returning a segment-drift response so an agent can re-verify (see MCP spec).

### 7.5 Screen-recording TCC through a signed app bundle

**Context:** macOS only delivers capture frames to a process the user granted Screen
Recording, and grants attach to a signed **app bundle**. **Decision:** ship the MCP server
as a signed `ShortsCastMCP.app`; the MCP client is configured to launch the **inner
Mach-O** (`…/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp`) so it inherits the bundle's
grant. **Consequence:** an agent-spawned server can capture. Trade-off: setup requires
pointing the client at the inner binary, not a bare executable — documented in INSTALL.md.

### 7.6 One SwiftPM package, no dependencies

**Decision:** everything is one package with library + executable targets. **Consequence:**
`swift build` / `swift test` is the whole toolchain; nothing to vendor or resolve; trivial
to reason about the dependency graph (it's the diagram in §2).

---

## 8. Testing strategy

The layering is what makes the suite (190 tests) possible:

- **Deterministic core → direct unit tests.** Clustering, the Auto-Director, the virtual
  camera, and the spring smoother are pure functions tested with hand-built `EventLog`s and
  exact assertions. No mocks needed.
- **Side-effecting shells → injected collaborators.** Capture, permissions, display
  enumeration, export, and app-launch are all injected into their callers (notably the MCP
  `Handlers`), so handlers and the editor model test without real hardware, permissions, or
  a display. Fakes stand in for the real collaborators.
- **Render → offline verification.** The compositor is checked by bitmap pixel assertions;
  the exporter by synthetic-video round-trips; a two-tone-source test guards against
  vertical flips.
- **Cross-cutting → integration-ish tests.** e.g. the MCP store reconstructs a bundle from
  disk after a simulated server restart; the full record→direct→export path is exercised
  end-to-end on synthetic input.

**What tests cannot cover:** live screen capture through the TCC grant (§7.5). That path is
verified manually — capture is confirmed working on macOS 12.6; the agent capture path
depends on granting the signed bundle the three permissions.

---

## Appendix — where things live

| Concern | Location |
|---------|----------|
| Auto-zoom math | `Sources/ShortsCastCore/{AutoDirector,Camera,Cursor}/`, `Director.swift` |
| Data models & bundle format | `Sources/ShortsCastCore/Models/`, `ShortsCastCapture/ProjectBundle.swift` |
| Capture & input | `Sources/ShortsCastCapture/` |
| Compositor & export | `Sources/ShortsCastRender/` |
| Editor model | `Sources/ShortsCastEditor/` |
| Agent server | `Sources/ShortsCastMCP/`, `Sources/shortscast-mcp/` |
| Packaging/signing | `Scripts/make-app.sh`, `Scripts/release.sh` |
| Design specs & plans | `docs/superpowers/` |
