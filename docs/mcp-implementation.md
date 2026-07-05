# ShortsCast MCP — Implementation Guide

A guide to the code in `Sources/ShortsCastMCP/` for anyone who needs to read or
change it. This describes the server **as built** (12 tools). For *why* the
agent surface exists and the product decisions behind it, see the design record
in [`docs/superpowers/specs/2026-07-01-shortscast-mcp-agent-design.md`](superpowers/specs/2026-07-01-shortscast-mcp-agent-design.md).

## What this layer is

`shortscast-mcp` is a thin control surface that lets an MCP client (Claude Code,
etc.) drive ShortsCast: start/stop a recording, inspect the auto-directed
segments, tune the camera and style, and export an mp4. It speaks
newline-delimited JSON-RPC 2.0 over stdio.

It contains **no recording, directing, or rendering logic of its own.** Every
tool binds arguments to the same libraries the CLI and GUI already use
(`ShortsCastCapture`, `ShortsCastCore`, `ShortsCastRender`, `ShortsCastEditor`).
Two invariants hold everywhere in this directory:

1. **stdout carries only JSON-RPC frames.** All diagnostics go to stderr via
   `ShortsCastMCP.log(_:)`. A stray `print` corrupts the protocol stream.
2. **The MCP layer is a pure control surface.** Tools call into the engine; they
   never modify it. New behavior belongs in the libraries, not here.

## File map

| File | Role |
|------|------|
| `RPC.swift` | Wire types: `LineTransport`, `RPCRequest`, `RPCResponse`/`RPCError`. |
| `JSONValue.swift` | Hand-rolled untyped JSON value — the boundary between the wire and typed Swift. |
| `MCPTool.swift` | `MCPTool` (name + schema + handler closure) and `ToolResult`. |
| `Server.swift` | The read/dispatch/write loop (`serve`) and the tool registry (`allTools`). |
| `Handlers.swift` | One method per tool. Holds injectable collaborators (DI). |
| `RecordingSessionStore.swift` | `actor` holding the single active recording + known bundles. |
| `StartArgs.swift` | Parses `start_recording`'s target trio (window / display / region). |
| `SettingsPatch.swift` | Partial-patch merge for director settings & style; re-segmentation classifier. |
| `EditsStore.swift` | Reads/writes the bundle's `project.json` (`ProjectEdits`). |
| `SessionPaths.swift` | Output dir (`~/Movies/ShortsCast`) and timestamped bundle names. |
| `SegmentSummary.swift` | Human summary of the input events inside a segment. |
| `CaptureSession.swift` | `CaptureSessionProtocol` so the store can be tested without real capture. |
| `AppLauncher.swift` | Opens a bundle in the editor app (`open_in_app`). |

## The request lifecycle

`ShortsCastMCP.serve(tools:transport:)` in `Server.swift` is the whole loop. It
reads one line at a time and returns when the transport hits EOF.

```swift
while let line = transport.readLine() {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { continue }
    guard let req = try? JSONDecoder().decode(RPCRequest.self, from: Data(trimmed.utf8)) else {
        log("drop unparseable line")          // → stderr, no reply
        continue
    }
    switch req.method { /* initialize | tools/list | tools/call | default */ }
    // encode response (if any) and transport.write(json)
}
```

The four methods:

- **`initialize`** — returns protocol version `2024-11-05`, a `tools` capability,
  and `serverInfo` (`shortscast` / `0.1.0`).
- **`tools/list`** — maps the registered `MCPTool`s to `{name, description,
  inputSchema}`.
- **`tools/call`** — looks up the tool by `params.name`, `await`s its handler
  with `params.arguments`, and wraps the returned `ToolResult` into the MCP
  shape: `{content: [{type:"text", text}], isError}`. An unknown name yields an
  error `ToolResult` (not a protocol error) so the model sees a readable
  message.
- **default** — a request with an `id` gets JSON-RPC error `-32601` (method not
  found); a **notification** (no `id`) gets no reply at all.

One tool call is therefore: `readLine` → decode `RPCRequest` → dispatch →
`tool.handler(args)` → `ToolResult` → encode `RPCResponse` → `transport.write`.
`LineTransport` is a protocol, so production runs over stdin/stdout while tests
feed scripted lines and capture the writes.

## Three patterns you'll reuse

Almost everything in this layer is an instance of one of these three ideas.

### 1. `JSONValue` — the untyped boundary

JSON-RPC params arrive shapeless. `JSONValue` (in `JSONValue.swift`) is a small
`Codable` enum — `null`/`bool`/`number`/`string`/`array`/`object` — that models
exactly that. It gives you two things:

- **Ergonomic reads** for one-off access: `args?["bundle"]?.stringValue`,
  `args?["index"]?.intValue`, `c["x"]?.doubleValue`.
- **A typed bridge** for anything structured: `decoded(_:)` re-encodes the
  `JSONValue` and decodes it into a `Codable` struct, and `from(_:)` goes the
  other way. `StartArgs.parse` and `SettingsPatch.apply` both cross the boundary
  this way instead of hand-walking the tree.

Prefer the accessors for a field or two; reach for `decoded(_:)` once a handler
needs a whole struct.

### 2. Handlers with injected collaborators (DI)

`Handlers` is one struct with a method per tool. Every side effect it needs is a
stored **closure with a production default**, supplied in `init`:

```swift
let resolveTarget: (StartArgs) throws -> ResolvedTarget
let makeSession: (ResolvedTarget, URL) -> CaptureSessionProtocol
let export: (URL, [OutputFormat], RenderStyle, AutoDirectorSettings, URL, [SegmentOverride]) throws -> [URL]
let permissionMissing: () -> [String]
let listDisplaysProvider: () -> [DisplayOption]
// … each defaulted to the real implementation in init
```

In production the defaults call `TargetResolver`, `RecordingController`,
`ExportJob`, `Permissions`, and so on. In tests you pass fakes, so a handler runs
its full control-flow — permission gate, target resolution, store mutation,
result shaping — **with no real capture, TCC prompt, display, or export.** That's
what makes the handlers unit-testable.

Each method returns through two private helpers: `ok(_ v: JSONValue)` serializes
a success payload; `err(_ message: String)` returns `ToolResult(text:,
isError: true)`. A handler's job is: validate args → call collaborators → shape
the result with `ok`/`err`.

### 3. `RecordingSessionStore` — the state machine

The store is an `actor`, so concurrent tool calls can't race its state. It holds
two things: the single `active` recording (at most one — `begin` throws `.busy`
if one already exists) and an ordered list of known bundle `entries`.

- `begin` / `end` are the lifecycle. `end` stops the capture session, appends an
  `Entry`, and hands back the `Recorder.Result`.
- `current`, `recent`, `register`, `update(bundle:mutate:)` are the accessors.
- **`entry(for:)` with disk fallback is the important one.** MCP clients restart
  the server routinely, so a bundle a tool references may not be in memory. When
  it isn't, `reconstruct(_:)` rebuilds the `Entry` from the on-disk
  `.shortscast` — reading its `EventLog` and persisted `ProjectEdits`, and
  re-deriving segments under those settings — then caches it. This is why
  `export`, `list_segments`, `set_*`, and `open_in_app` work across restarts as
  long as you pass a valid `bundle` path.

Per-segment overrides are keyed by **index**, and re-segmentation can change how
many segments there are (see the index-drift discussion in the design record).
`SettingsPatch.resegmentingFields` is the list of director fields that trigger a
re-cut; `set_director_settings` re-runs the `Director` and reports the new count
only when one of those fields changed.

## The 12 tools

All are registered in `ShortsCastMCP.allTools`. Handlers live in `Handlers.swift`.
"Bundle-addressed" tools accept an optional `bundle` path and resolve it through
`store.entry(for:)` (falling back to the most recent recording when omitted).

| Tool | Args | Touches | Returns |
|------|------|---------|---------|
| `start_recording` | `target` \| `display` \| `region` (mutually exclusive) | Permissions gate → `TargetResolver` → `RecordingController` → `store.begin` | `session_id`, `started_at`, `target`, `bundle_path` |
| `stop_recording` | `session_id` | `store.end`, then auto-directs once | `bundle_path`, `duration`, `event_count`, `segment_count` |
| `recording_status` | — | `store.current` | `active` or `session_id`/`elapsed`/`target` |
| `list_recordings` | — | in-memory entries + disk scan of output dir | `recordings[]` (path, created, duration, segments) |
| `list_displays` | — | `TargetResolver.displays()` | `displays[]` (index, w/h, is_main, label) |
| `list_windows` | — | `TargetResolver.windows()` | `windows[]` (app, title, target, label) |
| `list_segments` | `bundle`* | `entry(for:)` + `SegmentSummary` | `segments[]` with event summaries |
| `set_segment_camera` | `bundle`*, `index` (req), `zoom`, `center`, `zoom_in/out_duration` | upserts an override, writes `project.json` | `index`, `saved` |
| `set_director_settings` | `bundle`*, any `AutoDirectorSettings` field(s) | `SettingsPatch.apply`, re-cuts if resegmenting | `segments_changed` + counts (+ segments if re-cut) |
| `set_style` | `bundle`*, any `RenderStyle` field(s) | `SettingsPatch.apply` on style, writes `project.json` | `saved` |
| `export_recording` | `bundle`*, `format` (default `9:16`) | `ExportJob.run` honoring saved edits | `mp4_paths[]` |
| `open_in_app` | `bundle`* | `AppLauncher.open` | `opened` path |

\* optional; defaults to the most recent recording.

All edits (`set_segment_camera`, `set_director_settings`, `set_style`) persist to
the bundle's `project.json` via `EditsStore` — the **same file the GUI editor
reads and writes** — so agent edits, a later `export`, and the app all agree.

## Recipe: adding a tool

The common change. Say you want `delete_recording`:

1. **Handler** — add a method on `Handlers` returning `ok`/`err`:
   ```swift
   public func deleteRecording(_ args: JSONValue?) async -> ToolResult {
       do {
           let entry = try await store.entry(for: bundleURL(from: args))
           try removeBundle(entry.bundleURL)          // injected collaborator
           return ok(.object(["deleted": .string(entry.bundleURL.path)]))
       } catch RecordingSessionStore.StoreError.notFound {
           return err("No such recording.")
       } catch { return err("Delete failed: \(error)") }
   }
   ```
   If it needs a new side effect, add it as an injected closure on `Handlers`
   (`let removeBundle: (URL) throws -> Void`) with a production default in
   `init` — don't call `FileManager` directly, or you can't fake it in tests.

2. **Register** — add an `MCPTool` in `allTools` with a clear `description`
   (the model reads this) and an `inputSchema` built from the `obj`/`str`/`num`
   helpers:
   ```swift
   MCPTool(name: "delete_recording",
           description: "Delete a recording's .shortscast bundle from disk.",
           inputSchema: obj(["bundle": str])) { await h.deleteRecording($0) },
   ```

3. **Pin the registry** — add `"delete_recording"` to the expected set in
   `ToolRegistryTests` so the tool-count test stays honest.

4. **Test the handler** — construct `Handlers` with fakes and assert the JSON
   shape and the error paths, the way the existing handler tests do.

Two things a new tool must not do: write to stdout, and reach past the control
surface into engine logic. If it needs new engine behavior, add that to the
relevant library first and call into it.

## Testing

The DI in `Handlers` and the `CaptureSessionProtocol` seam in the store are what
make this layer testable without hardware. Handler tests inject fake resolvers,
sessions, exporters, and permission probes and assert on the returned
`ToolResult` JSON. `ToolRegistryTests` pins the exact set of tool names, so
adding or removing a tool without updating the expected set fails loudly.

The `serve` loop is tested by driving a fake `LineTransport` with scripted
JSON-RPC lines and inspecting the writes — covering `initialize`, `tools/list`,
`tools/call`, unknown methods, notifications, and unparseable input.

The one thing unit tests can't cover is macOS screen-recording permission (TCC):
capture frames are only delivered to a signed, granted `.app` bundle. That path
is verified by a manual smoke test against the installed
`ShortsCastMCP.app` — see the permissions section of the design record for the
setup.
