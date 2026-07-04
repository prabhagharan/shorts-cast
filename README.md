# ShortsCast

A macOS-native screen recorder for short-form tutorials. Record your screen, and
ShortsCast automatically produces a polished vertical (or square / portrait / wide)
video — with **click-driven auto-zoom** that follows what you're doing, a framed and
shadowed screen, a synthetic cursor with click ripples, and a background.

It runs three ways:

- **GUI app** — record, preview, tweak, and export.
- **Command line** — scriptable `record` and `export` binaries.
- **MCP agent server** — let Claude Desktop or Claude Code record *for* you (e.g. while
  it's doing a task in Chrome), then tune and export the result through tool calls.

Built in Swift / SwiftUI. Runs on **macOS 12 (Monterey) or later**. No external
dependencies. Screen capture uses AVFoundation (`AVCaptureScreenInput`), so it works on
Monterey where ScreenCaptureKit delivers no frames.

---

## What it does

| Feature | Detail |
|---------|--------|
| **Auto-zoom** | An "Auto-Director" analyzes recorded clicks/keystrokes/scrolls, clusters them into focus segments, and drives a virtual camera that zooms and pans to each — automatically. |
| **Multi-format** | One recording exports to **9:16**, **1:1**, **4:5**, or **16:9**, each via an auto-panning virtual camera that keeps the action in frame. |
| **Framing & polish** | Rounded-corner screen with drop shadow, solid/gradient background, a synthetic cursor, and click ripples — all composited with Core Image. |
| **Editable** | Every auto decision (per-segment zoom/center/easing, director tuning, render style, format) can be overridden and re-exported. |
| **Agent-drivable** | A hand-rolled MCP server exposes 12 tools so an AI agent can record, inspect segments, adjust the camera in plain language, and export. |

---

## Install (prebuilt app)

For non-developers who just want the app, see **[INSTALL.md](INSTALL.md)** — it walks
through unzipping, clearing the macOS Gatekeeper warning, and granting permissions.

## Permissions

Capture and auto-zoom need three macOS permissions (System Settings → Privacy & Security):

- **Screen Recording** — to capture frames
- **Accessibility** and **Input Monitoring** — to record the clicks/keystrokes that drive auto-zoom

macOS applies Accessibility and Input Monitoring only on the *next* launch, so **quit and
reopen** the app (or restart the MCP client) after granting them.

---

## Build from source

Requires Xcode 14.2+ / Swift 5.7+ on macOS 12+.

```bash
git clone git@github.com:prabhagharan/shorts-cast.git
cd shorts-cast
swift build            # build everything
swift test             # run the full suite (190 tests)
```

Package the signed `.app` bundles (GUI + MCP):

```bash
./Scripts/make-app.sh          # -> .build/ShortsCast.app, .build/ShortsCastMCP.app, ...
./Scripts/release.sh           # -> a distributable release zip with both apps
```

---

## Usage

### GUI app

```bash
open .build/ShortsCastApp.app
```

Open a recording, scrub the timeline, adjust segments in the inspector, save, and export.
Or hit **Record** to capture directly.

### Command line

**Record** a screen region to a `.shortscast` bundle (and optionally auto-direct it):

```bash
shortscast-rec --seconds 20 --out demo.shortscast \
  [--display N | --window <app-or-id> | --rect x,y,w,h] [--direct]
```

**Export** a finished MP4 (one or more formats) from a bundle:

```bash
shortscast-export demo.shortscast --format 9:16,1:1 --out ./out [--style style.json]
```

Valid format names: `9:16`, `1:1`, `4:5`, `16:9`.

### Agent (MCP)

Point Claude Desktop or Claude Code at the signed MCP bundle and ask it to record. Full
setup — including why the client must target the *inner* Mach-O so it inherits the app's
screen-recording grant — is in **[INSTALL.md → Agent (MCP) setup](INSTALL.md#agent-mcp-setup)**.

Quick version for Claude Code:

```bash
claude mcp add -s user shortscast \
  ~/Applications/ShortsCast/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp
```

Then, in a fresh session:

> "List my windows, start recording the Google Chrome one, wait while I do a task,
> then stop and export a 9:16 short."

Recordings land in `~/Movies/ShortsCast/`.

#### MCP tools (12)

| Tool | Purpose |
|------|---------|
| `start_recording` | Start an open-ended recording of a window, display, or region |
| `stop_recording` | Stop, finalize the bundle, and auto-direct it |
| `recording_status` | Whether a recording is active, plus elapsed time and target |
| `list_recordings` | Recent recordings (path, created, duration, segment count) |
| `list_displays` | Attached displays with the `index` to target, resolution, main flag |
| `list_windows` | On-screen app windows with a `target` usable by `start_recording` |
| `list_segments` | Auto-directed focus segments with an event-derived summary of each |
| `set_segment_camera` | Override one segment's zoom, center, and ease in/out |
| `set_director_settings` | Patch global auto-director tuning; reports if segments were re-cut |
| `set_style` | Patch render style (padding, corner radius, shadow, cursor, ripples) |
| `export_recording` | Export an MP4 honoring saved camera/settings/style |
| `open_in_app` | Open a recording in the ShortsCast editor for manual review |

The server speaks newline-delimited JSON-RPC 2.0 over stdio (`initialize` / `tools/list`
/ `tools/call`). Camera and tuning edits persist to the bundle's `project.json`, so the
CLI, GUI, and agent all agree on the same state.

---

## Architecture

A layered Swift package — pure, deterministic logic at the core, side-effecting shells at
the edges. Everything below the executables is unit-tested.

```
ShortsCastCore      Pure engine: event models, clustering, Auto-Director (auto-zoom
                    camera path), VirtualCamera format-fitting, spring smoothing.
      │
ShortsCastCapture   Screen + input capture (AVFoundation + CGEventTap), target
                    resolution (display / window / region), .shortscast bundle I/O.
      │
ShortsCastRender    Core Image compositor + H.264 MP4 exporter.
      │
ShortsCastEditor    Headless editor model: open → direct → edit → preview → export.
      │
   ┌──┴─────────────┬──────────────┬─────────────────┐
shortscast-rec  shortscast-    shortscast-app     ShortsCastMCP
  (CLI record)   export (CLI)   (SwiftUI GUI)     └─ shortscast-mcp (agent server)
```

- **Executables:** `shortscast-rec`, `shortscast-export`, `shortscast-app`, `shortscast-mcp`.
- **Libraries:** `ShortsCastCore`, `ShortsCastCapture`, `ShortsCastRender`, `ShortsCastEditor`, `ShortsCastMCP`.
- The MCP layer is a **pure control surface** — it adds no engine logic, only wraps the
  existing libraries behind tool calls.

Design specs and implementation plans live under [`docs/`](docs/).

---

## Development

- **TDD throughout** — write the failing test first. The suite is 190 tests.
- `swift test` runs everything; `swift test --filter <SuiteName>` runs one suite.
- The MCP handlers inject all side-effecting collaborators (capture, permissions, display
  enumeration, export), so they unit-test without real hardware or permissions.

## Status

The core engine, capture, compositor/export, editor, SwiftUI app, and MCP agent server are
all implemented and merged. Live screen capture is verified on macOS 12.6. The MCP agent
path's end-to-end capture depends on granting the signed `ShortsCastMCP.app` the three
permissions above.
