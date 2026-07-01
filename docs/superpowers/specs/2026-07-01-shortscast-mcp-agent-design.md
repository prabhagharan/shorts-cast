# ShortsCast MCP — Agent-Driven Recording

**Date:** 2026-07-01
**Status:** Design approved, pending spec review

## Goal

Let an AI agent (Claude Desktop or Claude Code) drive ShortsCast: start a
recording, do a task (e.g. browser automation in Chrome), stop, tune the camera,
and export a finished vertical short — all through tool calls. The motivating
scenario is **the agent recording its own work**: it starts capture, performs
an open-ended task, then stops, so recording duration equals task length rather
than a fixed `--seconds`.

It also supports a **feedback loop**: after an export the user speaks in plain
language ("zoom tighter on that click", "everything zooms too hard", "use a
lighter background"), the agent maps that onto per-segment / global-director /
style edits, re-exports, and the user reacts again.

Because Claude Desktop can only reach external tools via **MCP**, the interface
is an MCP server. The same server also works for Claude Code.

## Non-goals (explicitly out of scope)

- **Live semantic camera markers** ("zoom here now" mid-recording). This "Level 2"
  feature needs a new agent-hint event type in `EventLog` plus director support.
  Deferred; may be designed as a fast-follow once real agent recordings exist.
- **Semantic segment labels in Core** (e.g. naming a segment "address bar click").
  `FocusSegment` has no label field and we are not adding one.
- **Local HTTP control daemon** and **multi-recording concurrency**. One active
  recording at a time; single stdio process.
- **Engine/Core changes generally.** This work is a control surface over existing
  libraries. If a task appears to need a Core change, stop and re-scope.

## Architecture

New executable target **`shortscast-mcp`** added to `Package.swift`, depending on
`ShortsCastCapture`, `ShortsCastRender`, `ShortsCastCore`, `ShortsCastEditor`
(for `ProjectEdits`). **No external dependency:** the MCP protocol is hand-rolled.

**Why not the official MCP Swift SDK:** it requires macOS 13 / Swift 6.1, which
would raise the whole package floor from macOS 12 and would not run on the
target Monterey machine. MCP's stdio transport is just newline-delimited
JSON-RPC 2.0, and a tools-only server needs only three request methods
(`initialize`, `tools/list`, `tools/call`) plus the `notifications/initialized`
ack — ~150 lines we own, keeping the package on macOS 12 / Swift 5.7 with zero
dependencies. Logs go to **stderr** (stdout is reserved for JSON-RPC frames).

Core state lives in a single `RecordingSessionStore` (a Swift `actor`):

- The one active `RecordingController` (if a recording is in progress), with its
  `session_id`, `started_at`, and resolved-target description.
- A registry of produced bundles (path, created time, duration, cached focus
  segments, current `ProjectEdits`).

The process is **launched by the client and stays alive** as a persistent stdio
server — which is precisely what allows a single recording to span the agent's
whole task across separate `start`/`stop` tool calls.

Each tool maps 1:1 onto existing code: `TargetResolver` for targeting,
`RecordingController.start()/stop()`, `Director.direct(log:overrides:)` for
segments/camera path, `ExportJob.run(...)` for export, `NSWorkspace` to launch
the app.

**Run-loop note (implementation risk to resolve):** the `CGEventTap` used by
`EventTap` needs a run loop on some thread, while the MCP SDK is async/await and
AVFoundation delivers frames on its own queue. The server must keep a run loop
alive for the event tap without blocking the MCP stdio loop. Resolve concretely
during the permissions spike (below).

## Tool surface (10 tools)

| Tool | Params | Returns |
|---|---|---|
| `start_recording` | `target`: app/window name (e.g. `"Google Chrome"`) **or** `display` index **or** `region` {x,y,w,h} — mutually exclusive, mirrors the CLI | `session_id`, `started_at`, resolved target description |
| `stop_recording` | `session_id` (optional, defaults to active) | `bundle_path`, `duration`, `event_count`, `segment_count` |
| `recording_status` | — | active session {id, elapsed, target} or "none" |
| `list_recordings` | — | recent bundles + exports: path, timestamp, duration |
| `list_segments` | `bundle` (optional, defaults to most recent) | per-segment: `index`, `start`, `end`, `zoom`, `center` {x,y}, ease durations, and an **event-derived `summary`** |
| `set_segment_camera` | `bundle` (optional), `index`, any of `zoom`, `center`, `zoom_in_duration`, `zoom_out_duration` | updated segment |
| `set_director_settings` | `bundle` (optional), partial patch of any `AutoDirectorSettings` field(s) | applied settings + `segments_changed` flag + old→new segment count + fresh `list_segments` when a **resegmenting** field changed (see below) |
| `set_style` | `bundle` (optional), partial patch of any `RenderStyle` field(s) | applied style (never resegments) |
| `export_recording` | `bundle` (optional), `auto_direct` (default true), `format`/`quality` (default vertical 9:16) | `mp4_path` |
| `open_in_app` | `bundle` (optional) | launches `shortscast-app` on the bundle |

**Concurrency:** `start_recording` while a session is active returns a clear
error rather than starting a second capture. `stop`/`list_segments`/`export`
with no bundle default to the most recent.

**Defaults for the agent path:** bundles and mp4s land in
`~/Movies/ShortsCast/<timestamp>.{shortscast,mp4}`; auto-director on; vertical
9:16 short — so a bare `start → stop → export` yields a shareable clip with no
tuning.

## Recording lifecycle & data flow

```
start_recording → TargetResolver.resolve → RecordingController.start()
                → store {session_id, started_at, target} as the active session
   … agent performs its open-ended task …
stop_recording  → controller.stop() writes the .shortscast bundle
                → Director.direct(log, overrides: []) → cache focus segments
                → return {bundle_path, duration, event_count, segment_count}

list_segments         → cached segments + event-derived summary per segment
set_segment_camera    → upsertOverride(...) into the session's ProjectEdits,
                        AND write project.json into the bundle (GUI parity)
set_director_settings → patch ProjectEdits.settings, write project.json, re-direct;
                        if a resegmenting field changed, return fresh list_segments
set_style             → patch ProjectEdits.style, write project.json (no re-direct)
export_recording      → load overrides+settings+style from project.json →
                        ExportJob.run(settings:style:overrides:)
open_in_app           → NSWorkspace launches shortscast-app on the bundle
```

## Tuning & feedback (Level 1 — no engine changes)

Post-recording only. Three levels of tuning, all backed by existing structures
(`ProjectEdits` = `overrides` + `settings` + `style`) that `ExportJob.run`
already consumes — so none of this touches Core/Render logic:

1. **Per-segment** — `set_segment_camera`, a thin wrapper over `upsertOverride`
   on `SegmentOverride` (`center`, `zoom`, `zoomInDuration?`, `zoomOutDuration?`).
2. **Global director feel** — `set_director_settings`, a partial patch over
   `AutoDirectorSettings`. Uses the type's existing tolerant per-field decoding,
   so the agent sends only the fields it wants (e.g. "too fast" → raise
   `zoomInDuration`/`zoomOutDuration`; "less aggressive" → lower `defaultZoom`).
3. **Look** — `set_style`, a partial patch over `RenderStyle` (background,
   `paddingFraction`, `cornerRadius`, shadow, cursor…).

**Everything persists into the bundle.** Each setter writes the session's
`ProjectEdits` to the bundle's `project.json` — the same structure the GUI editor
reads. `export_recording` loads it and passes `settings:`, `style:`, and
`overrides:` into `ExportJob.run` (which does **not** auto-read `project.json`).
Result: export, `open_in_app`, and the GUI all agree, and a human can pick up in
the app where the agent left off.

Camera vocabulary is 2D: **where it looks** (`center`), **how tight** (`zoom`),
**how fast** (`zoomInDuration`/`zoomOutDuration`). There is no 3D tilt/angle.

### Precedence & the index-drift caveat

At export the pipeline is:

```
clustered = EventClusterer(settings).segments(from: log)   ← settings shape segmentation
dwell     = DwellDetector(settings).segments(from: log)    ← settings shape segmentation
combined  = mergeNonOverlapping(clustered, dwell)          ← ordered segment list
segments  = applyOverrides(combined, overrides)            ← per-segment edits patched LAST, by index
path      = AutoDirector(settings).cameraPath(segments…)   ← easing uses seg.value ?? settings.value
```

- **Per-segment overrides win** for whatever fields they set: `applyOverrides`
  runs last (`seg.zoom = override.zoom`), and easing falls back
  `seg.zoomInDuration ?? settings.zoomInDuration`. So a global
  `set_director_settings` only moves the segments/fields the user has **not**
  pinned. Pinning segment 3 to 2.8× survives a later global `defaultZoom` drop.
- **Index drift** is the one caveat: overrides are keyed by segment **index**, and
  a subset of settings control **segmentation itself**. Changing those can change
  the number/order of segments, so an indexed override may attach to a different
  moment — not the global *overriding* the edit, but the edit's *target shifting*.

**Field classification (the server enforces this):**

- **Resegmenting** (may change segment count/order): `clusterTimeGap`,
  `clusterRadius`, `dwellTime`, `dwellRadius`, `denseEventCount`, `clickWeight`,
  `keyWeight`, `scrollWeight`.
- **Safe / feel-only** (never resegment): `defaultZoom`, `maxZoom`, `restingZoom`,
  `inactivityTimeout`, `zoomInDuration`, `zoomOutDuration`, `dwellZoom`,
  `denseZoomBonus`, `restingAnchor`, `zoomOutInPlace`, and all `RenderStyle`
  fields.

**Mitigation:** when `set_director_settings` patches any resegmenting field, the
server re-directs and returns `segments_changed: true`, the old→new segment
count, and the fresh `list_segments` — so drift is immediately visible and the
agent/user can re-verify the per-segment overrides. Safe-field patches return
`segments_changed: false`.

## Event-derived segment summary

`list_segments` includes a human-readable `summary` per segment, computed purely
at the MCP layer from the bundle's `EventLog` (no Core changes). For each segment
`[start, end)`, count the `RecordingEvent`s that fall inside and format them,
e.g. **"3 clicks (2 left, 1 right), 12 keystrokes, 1 scroll"**.

Honest constraints from the real event model:

- Event types are `click` (with `left`/`right`/`other` button), `key`, `scroll`
  (with `deltaY`), and `cursor` (movement samples).
- `key` events carry **no character/text** — the summary reports keystroke
  *counts* ("12 keystrokes"), never the typed string.
- `cursor` events are movement samples; excluded from the summary (or folded into
  a "cursor active" note) to avoid noise.

## macOS permissions (TCC) — the one real risk

Screen Recording (capture) and Accessibility (event tap) grants attach to the
**signed binary's identity and path**. Therefore:

- `shortscast-mcp` must be **code-signed with a stable identity** and installed to
  a **fixed path** (e.g. `~/Applications/ShortsCast/shortscast-mcp`) so grants
  persist across launches; the client config points at that absolute path.
- First invocation triggers the system prompts; the user grants once.
- Headless helpers spawned by another app can have awkward TCC attribution.

**Sequencing: the first implementation task is a permissions spike** — prove a
signed helper launched over stdio by Claude Desktop can hold Screen Recording and
run the event tap. This also resolves the run-loop question. Everything else is
low-risk; de-risk this first before building the full tool surface.

## Distribution & client config

- Build + sign `shortscast-mcp` (macOS 12 / Swift 5.7, no external deps), install
  to the fixed path. Extend `Scripts/make-app.sh` / `Scripts/release.sh` to build
  and sign the helper.
- **Claude Desktop** — `claude_desktop_config.json`:
  ```json
  { "mcpServers": { "shortscast": { "command": "/Users/<you>/Applications/ShortsCast/shortscast-mcp" } } }
  ```
- **Claude Code** — `claude mcp add shortscast /Users/<you>/Applications/ShortsCast/shortscast-mcp`
  (or a project `.mcp.json`).
- Ship both snippets in `INSTALL.md`.

## Testing

**Unit (the glue we're adding):**
- Tool argument validation, mirroring `CLIOptionsTests` (missing/invalid/mutually
  exclusive `target`).
- `RecordingSessionStore` actor state machine: start-while-active → error,
  stop-with-none → error, defaulting to active / most-recent bundle.
- `target` spec → `TargetResolver` mapping.
- `set_segment_camera` → `upsertOverride` and `project.json` round-trip.
- `set_director_settings` / `set_style` → partial-patch semantics (unset fields
  preserved), `project.json` round-trip.
- **Field classification**: `set_director_settings` on a resegmenting field
  returns `segments_changed: true` + fresh segments; on a safe field returns
  `segments_changed: false`. Assert the classification table explicitly.
- `list_segments` event-derived summary: given a synthetic `EventLog`, assert the
  counts/wording per segment window.
- Export wiring: `settings`, `style`, and `overrides` all loaded from
  `project.json` and passed through to `ExportJob.run`.

Capture, render, and director code is already covered by existing tests; the MCP
layer tests the request→library-call mapping and the state machine.

**Integration (manual, live):** one end-to-end `start → stop → export` run, using
the same "live-verified" approach the capture layer already relies on (screen
capture cannot be unit-tested).

**Config smoke test:** register the server in a client and confirm all 10 tools
list and a trivial call (`recording_status`) responds.

## Implementation order (suggested)

1. **Permissions spike** — signed stdio helper holds Screen Recording + runs the
   event tap when launched by Claude Desktop. Resolve run-loop integration.
2. `RecordingSessionStore` actor + `start`/`stop`/`recording_status` +
   `list_recordings`.
3. `list_segments` with event-derived summary.
4. `set_segment_camera` + `project.json` persistence + `export_recording`.
5. `set_director_settings` (with field classification + drift response) +
   `set_style`.
6. `open_in_app`.
7. Packaging/signing + client config + `INSTALL.md`.
