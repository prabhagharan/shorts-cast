# ShortsCast MCP (Agent-Driven Recording) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a hand-rolled MCP (stdio JSON-RPC) server, `shortscast-mcp`, that lets Claude Desktop/Code drive ShortsCast — start/stop task-length recordings, tune the camera (per-segment + global director + style), and export a finished vertical short — with zero engine changes.

**Architecture:** A new library target `ShortsCastMCP` holds all logic (protocol plumbing, tool registry, a `RecordingSessionStore` actor, tool handlers) and a thin `shortscast-mcp` executable calls `ShortsCastMCP.run()`. Tools map 1:1 onto existing library calls (`TargetResolver`, `RecordingController`, `Director`, `ExportJob`, `ProjectEdits`). Camera/tuning edits persist into each `.shortscast` bundle's `project.json` so export, `open_in_app`, and the GUI all agree.

**Tech Stack:** Swift 5.7, SwiftPM, macOS 12. No external dependencies — MCP is newline-delimited JSON-RPC 2.0 over stdin/stdout, implemented by hand.

## Global Constraints

- **Toolchain floor:** `swift-tools-version:5.7`, `platforms: [.macOS(.v12)]` — do NOT raise these. No external package dependencies.
- **stdout is reserved for JSON-RPC frames only.** All diagnostics/logs go to **stderr** (`FileHandle.standardError`). A stray `print()` to stdout corrupts the protocol.
- **No Core/Render/Capture/Editor engine changes.** This target is a control surface over existing APIs. If a task appears to need an engine change, stop and re-scope.
- **Frame delivery requires a signed `.app` bundle.** macOS will not deliver screen-capture frames to a bare CLI binary. The server binary must run as the inner Mach-O of a signed `.app` (stable identity), exactly like the existing `ShortsCastRec.app` in `Scripts/make-app.sh`. Client config points `command` at `…/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp`.
- **One active recording at a time.** `start_recording` while a session is live returns an error, not a second capture.
- **MCP protocol version string:** reply to `initialize` with `"protocolVersion": "2024-11-05"`.
- **Tool result shape:** every tool returns MCP content `{ "content": [{"type":"text","text": <string>}], "isError": <bool> }`. Structured payloads (e.g. `list_segments`) are returned as a JSON **string** inside that text block.
- **Default output dir:** `~/Movies/ShortsCast/`. Bundles/exports are named `<timestamp>.shortscast` / `<base>-<format>.mp4`.

## File Structure

New library target `Sources/ShortsCastMCP/`:
- `JSONValue.swift` — a minimal `Codable` JSON value enum + decode/accessor helpers. The one shared utility.
- `RPC.swift` — `RPCRequest`/`RPCResponse`/`RPCError` structs; the `LineTransport` protocol; the read-dispatch-write loop.
- `MCPTool.swift` — `MCPTool` (name, description, inputSchema, handler) and `ToolResult`.
- `Server.swift` — builds the tool list, handles `initialize`/`tools/list`/`tools/call`, wires the transport. Exposes `ShortsCastMCP.run()`.
- `RecordingSessionStore.swift` — the `actor`: active session + produced-bundle registry.
- `CaptureSession.swift` — `CaptureSessionProtocol` + `RecordingController` conformance (for test injection).
- `SessionPaths.swift` — default output dir + timestamped names.
- `StartArgs.swift` — parse `start_recording` arguments → `(displayIndex?, windowQuery?, region?)` (pure, mirrors `CLIOptions`).
- `SegmentSummary.swift` — event-derived per-segment summary from `EventLog`.
- `EditsStore.swift` — read/write `ProjectEdits` (`project.json`) inside a bundle.
- `SettingsPatch.swift` — partial-patch decode for `AutoDirectorSettings`/`RenderStyle` + the resegmenting-field classification.
- `Handlers.swift` — the 10 tool handler closures binding args → library calls → `ToolResult`.

New executable `Sources/shortscast-mcp/main.swift` — calls `ShortsCastMCP.run()`.

New tests `Tests/ShortsCastMCPTests/` — one file per logic area.

Modified: `Package.swift` (add targets); `Scripts/make-app.sh` (bundle the MCP helper); `Scripts/release.sh` (build/sign helper); `INSTALL.md` (client config).

---

### Task 1: Scaffold targets + JSON-RPC stdio plumbing + minimal server

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ShortsCastMCP/JSONValue.swift`
- Create: `Sources/ShortsCastMCP/RPC.swift`
- Create: `Sources/ShortsCastMCP/MCPTool.swift`
- Create: `Sources/ShortsCastMCP/Server.swift`
- Create: `Sources/shortscast-mcp/main.swift`
- Test: `Tests/ShortsCastMCPTests/JSONValueTests.swift`
- Test: `Tests/ShortsCastMCPTests/RPCLoopTests.swift`

**Interfaces:**
- Produces:
  - `enum JSONValue: Codable, Equatable { case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue]) }` with `subscript(String) -> JSONValue?`, `var stringValue: String?`, `var doubleValue: Double?`, `var intValue: Int?`, `var boolValue: Bool?`, `var arrayValue: [JSONValue]?`, and `func decoded<T: Decodable>(_ type: T.Type) throws -> T`, plus `static func from<T: Encodable>(_ value: T) throws -> JSONValue`.
  - `struct RPCRequest: Decodable { let jsonrpc: String; let id: JSONValue?; let method: String; let params: JSONValue? }`
  - `struct RPCError: Encodable, Equatable { let code: Int; let message: String }`
  - `struct RPCResponse: Encodable { let jsonrpc: String; let id: JSONValue?; let result: JSONValue?; let error: RPCError? }` with `static func ok(id:JSONValue?, _ result: JSONValue) -> RPCResponse` and `static func fail(id:JSONValue?, code:Int, message:String) -> RPCResponse`.
  - `protocol LineTransport: AnyObject { func readLine() -> String?; func write(_ line: String) }`
  - `struct ToolResult { let text: String; let isError: Bool }` and `struct MCPTool { let name: String; let description: String; let inputSchema: JSONValue; let handler: (JSONValue?) async -> ToolResult }` (in `MCPTool.swift`).
  - `enum ShortsCastMCP { static func serve(tools: [MCPTool], transport: LineTransport) async; static func run() }` (in `Server.swift`).

- [ ] **Step 1: Add targets to Package.swift**

In `Package.swift`, add to `products`:
```swift
        .executable(name: "shortscast-mcp", targets: ["shortscast-mcp"]),
```
add to `targets`:
```swift
        .target(name: "ShortsCastMCP",
                dependencies: ["ShortsCastCore", "ShortsCastCapture", "ShortsCastRender", "ShortsCastEditor"]),
        .testTarget(name: "ShortsCastMCPTests", dependencies: ["ShortsCastMCP"]),
        .executableTarget(name: "shortscast-mcp", dependencies: ["ShortsCastMCP"]),
```

- [ ] **Step 2: Write the failing test for JSONValue**

Create `Tests/ShortsCastMCPTests/JSONValueTests.swift`:
```swift
import XCTest
@testable import ShortsCastMCP

final class JSONValueTests: XCTestCase {
    func test_roundTrip_object() throws {
        let json = #"{"a":1,"b":"x","c":[true,null]}"#
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(v["a"]?.doubleValue, 1)
        XCTAssertEqual(v["b"]?.stringValue, "x")
        XCTAssertEqual(v["c"]?.arrayValue?.first?.boolValue, true)
        let reEncoded = try JSONEncoder().encode(v)
        let back = try JSONDecoder().decode(JSONValue.self, from: reEncoded)
        XCTAssertEqual(v, back)
    }

    struct Point: Codable, Equatable { var x: Double; var y: Double }

    func test_decoded_intoCodable() throws {
        let v = try JSONValue.from(Point(x: 3, y: 4))
        XCTAssertEqual(try v.decoded(Point.self), Point(x: 3, y: 4))
    }

    func test_intValue_fromWholeNumber() throws {
        let v = try JSONDecoder().decode(JSONValue.self, from: Data("7".utf8))
        XCTAssertEqual(v.intValue, 7)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter JSONValueTests`
Expected: FAIL — `ShortsCastMCP` has no `JSONValue` (compile error).

- [ ] **Step 4: Implement JSONValue**

Create `Sources/ShortsCastMCP/JSONValue.swift`:
```swift
import Foundation

/// A minimal, order-agnostic JSON value used for JSON-RPC params/results and for
/// bridging arbitrary tool arguments into typed Codable structs.
public enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var doubleValue: Double? { if case .number(let d) = self { return d }; return nil }
    public var intValue: Int? { if case .number(let d) = self { return Int(d) }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    /// Re-encode this value and decode it into a typed Codable struct.
    public func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
    /// Bridge a Codable value into a JSONValue.
    public static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
```

- [ ] **Step 5: Run JSONValue test to verify it passes**

Run: `swift test --filter JSONValueTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Write the failing test for the RPC dispatch loop**

Create `Tests/ShortsCastMCPTests/RPCLoopTests.swift`:
```swift
import XCTest
@testable import ShortsCastMCP

final class FakeTransport: LineTransport {
    var inbox: [String]
    var outbox: [String] = []
    init(_ lines: [String]) { inbox = lines }
    func readLine() -> String? { inbox.isEmpty ? nil : inbox.removeFirst() }
    func write(_ line: String) { outbox.append(line) }
}

final class RPCLoopTests: XCTestCase {
    func test_initialize_thenToolsList() async throws {
        let ping = MCPTool(name: "ping", description: "returns pong",
                           inputSchema: .object(["type": .string("object")])) { _ in
            ToolResult(text: "pong", isError: false)
        }
        let t = FakeTransport([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ping","arguments":{}}}"#
        ])
        await ShortsCastMCP.serve(tools: [ping], transport: t)

        XCTAssertEqual(t.outbox.count, 3) // notification produces no response
        let initResp = try JSONDecoder().decode(JSONValue.self, from: Data(t.outbox[0].utf8))
        XCTAssertEqual(initResp["result"]?["protocolVersion"]?.stringValue, "2024-11-05")
        let listResp = try JSONDecoder().decode(JSONValue.self, from: Data(t.outbox[1].utf8))
        XCTAssertEqual(listResp["result"]?["tools"]?.arrayValue?.first?["name"]?.stringValue, "ping")
        let callResp = try JSONDecoder().decode(JSONValue.self, from: Data(t.outbox[2].utf8))
        XCTAssertEqual(callResp["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue, "pong")
        XCTAssertEqual(callResp["result"]?["isError"]?.boolValue, false)
    }

    func test_unknownTool_returnsIsError() async throws {
        let t = FakeTransport([
            #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#
        ])
        await ShortsCastMCP.serve(tools: [], transport: t)
        let resp = try JSONDecoder().decode(JSONValue.self, from: Data(t.outbox[0].utf8))
        XCTAssertEqual(resp["result"]?["isError"]?.boolValue, true)
    }
}
```

- [ ] **Step 7: Run test to verify it fails**

Run: `swift test --filter RPCLoopTests`
Expected: FAIL — `LineTransport`, `MCPTool`, `ToolResult`, `ShortsCastMCP.serve` undefined.

- [ ] **Step 8: Implement RPC types**

Create `Sources/ShortsCastMCP/RPC.swift`:
```swift
import Foundation

public protocol LineTransport: AnyObject {
    func readLine() -> String?
    func write(_ line: String)
}

public struct RPCRequest: Decodable {
    public let jsonrpc: String
    public let id: JSONValue?
    public let method: String
    public let params: JSONValue?
}

public struct RPCError: Encodable, Equatable {
    public let code: Int
    public let message: String
}

public struct RPCResponse: Encodable {
    public let jsonrpc: String
    public let id: JSONValue?
    public let result: JSONValue?
    public let error: RPCError?

    public static func ok(id: JSONValue?, _ result: JSONValue) -> RPCResponse {
        RPCResponse(jsonrpc: "2.0", id: id, result: result, error: nil)
    }
    public static func fail(id: JSONValue?, code: Int, message: String) -> RPCResponse {
        RPCResponse(jsonrpc: "2.0", id: id, result: nil, error: RPCError(code: code, message: message))
    }
}
```

- [ ] **Step 9: Implement MCPTool + ToolResult**

Create `Sources/ShortsCastMCP/MCPTool.swift`:
```swift
import Foundation

public struct ToolResult {
    public let text: String
    public let isError: Bool
    public init(text: String, isError: Bool) { self.text = text; self.isError = isError }
}

public struct MCPTool {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public let handler: (JSONValue?) async -> ToolResult
    public init(name: String, description: String, inputSchema: JSONValue,
                handler: @escaping (JSONValue?) async -> ToolResult) {
        self.name = name; self.description = description
        self.inputSchema = inputSchema; self.handler = handler
    }
}
```

- [ ] **Step 10: Implement the server loop**

Create `Sources/ShortsCastMCP/Server.swift`:
```swift
import Foundation

public enum ShortsCastMCP {
    /// Read one JSON-RPC line at a time, dispatch, and write responses. Returns when
    /// the transport is exhausted (EOF). Notifications (no `id`) produce no response.
    public static func serve(tools: [MCPTool], transport: LineTransport) async {
        let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        while let line = transport.readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let req = try? JSONDecoder().decode(RPCRequest.self, from: Data(trimmed.utf8)) else {
                log("drop unparseable line")
                continue
            }
            let response: RPCResponse?
            switch req.method {
            case "initialize":
                response = .ok(id: req.id, .object([
                    "protocolVersion": .string("2024-11-05"),
                    "capabilities": .object(["tools": .object([:])]),
                    "serverInfo": .object(["name": .string("shortscast"), "version": .string("0.1.0")])
                ]))
            case "tools/list":
                let list = tools.map { t in
                    JSONValue.object(["name": .string(t.name),
                                      "description": .string(t.description),
                                      "inputSchema": t.inputSchema])
                }
                response = .ok(id: req.id, .object(["tools": .array(list)]))
            case "tools/call":
                let name = req.params?["name"]?.stringValue ?? ""
                let args = req.params?["arguments"]
                let result: ToolResult
                if let tool = byName[name] {
                    result = await tool.handler(args)
                } else {
                    result = ToolResult(text: "Unknown tool: \(name)", isError: true)
                }
                response = .ok(id: req.id, .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(result.text)])]),
                    "isError": .bool(result.isError)
                ]))
            default:
                // Notifications and unknown methods with no id get no reply.
                response = req.id == nil ? nil : .fail(id: req.id, code: -32601,
                                                       message: "Method not found: \(req.method)")
            }
            if let response, let data = try? JSONEncoder().encode(response),
               let json = String(data: data, encoding: .utf8) {
                transport.write(json)
            }
        }
    }

    public static func log(_ message: String) {
        FileHandle.standardError.write(Data(("[shortscast-mcp] " + message + "\n").utf8))
    }
}
```

- [ ] **Step 11: Run RPC test to verify it passes**

Run: `swift test --filter RPCLoopTests`
Expected: PASS (2 tests).

- [ ] **Step 12: Create the executable entry point (stdio transport)**

Create `Sources/shortscast-mcp/main.swift`:
```swift
import Foundation
import ShortsCastMCP

/// Line-buffered stdin/stdout transport. stdout carries ONLY JSON-RPC frames.
final class StdioTransport: LineTransport {
    private var buffer = Data()
    func readLine() -> String? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            let chunk = FileHandle.standardInput.availableData
            if chunk.isEmpty { // EOF
                if buffer.isEmpty { return nil }
                let rest = String(data: buffer, encoding: .utf8); buffer.removeAll(); return rest
            }
            buffer.append(chunk)
        }
    }
    func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

// Registered tools are wired in later tasks via ShortsCastMCP.allTools().
let transport = StdioTransport()
await ShortsCastMCP.serve(tools: ShortsCastMCP.allTools(), transport: transport)
```

Add a temporary stub in `Server.swift` so it compiles now (replaced in Task 13's wiring):
```swift
public extension ShortsCastMCP {
    static func allTools() -> [MCPTool] {
        [ MCPTool(name: "ping", description: "Health check; returns pong.",
                  inputSchema: .object(["type": .string("object"), "properties": .object([:])])) { _ in
            ToolResult(text: "pong", isError: false) } ]
    }
}
```

- [ ] **Step 13: Build the whole package**

Run: `swift build`
Expected: builds `shortscast-mcp` with no errors.

- [ ] **Step 14: Commit**

```bash
git add Package.swift Sources/ShortsCastMCP Sources/shortscast-mcp Tests/ShortsCastMCPTests
git commit -m "feat(mcp): scaffold ShortsCastMCP + hand-rolled JSON-RPC stdio server"
```

---

### Task 2: Permissions & capture spike (bundle, grant, live capture) — MANUAL

This is the de-risking spike from the spec. It proves a signed `.app`-wrapped MCP binary, launched by its inner Mach-O, can (a) speak JSON-RPC over stdio and (b) actually receive screen-capture frames (holds Screen Recording) while running the event tap. No new unit tests — capture/TCC cannot be unit-tested; verification is live.

**Files:**
- Modify: `Sources/ShortsCastMCP/Server.swift` (temporary `capture_test` tool)
- Modify: `Scripts/make-app.sh` (add `ShortsCastMCP.app` bundling)

- [ ] **Step 1: Add a temporary `capture_test` tool**

In `Server.swift`, extend `allTools()` to also include (remove after this task):
```swift
        MCPTool(name: "capture_test",
                description: "Spike: record 2s of the main display to a temp bundle.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])])) { _ in
            do {
                Permissions.request()
                let missing = Permissions.status().missingNames
                guard missing.isEmpty else { return ToolResult(text: "Missing: \(missing)", isError: true) }
                let target = try TargetResolver.resolve(displayIndex: nil, windowQuery: nil, region: nil)
                let out = FileManager.default.temporaryDirectory
                    .appendingPathComponent("spike-\(UUID().uuidString).shortscast")
                let iso = ISO8601DateFormatter().string(from: Date())
                let r = try await Recorder.record(target: target, seconds: 2, outBundle: out,
                                                  appVersion: ShortsCastCapture.version, createdISO: iso)
                return ToolResult(text: "Wrote \(r.bundleURL.path), events=\(r.eventLog.events.count)", isError: false)
            } catch {
                return ToolResult(text: "capture failed: \(error)", isError: true)
            }
        }
```
Add imports at the top of `Server.swift`: `import ShortsCastCapture` and `import ShortsCastCore`.

- [ ] **Step 2: Add MCP bundling to make-app.sh**

In `Scripts/make-app.sh`, after the GUI editor app block, append a third bundle. `LSUIElement` is true (background helper, no dock icon):
```bash
# --- MCP server (background helper; frame delivery needs a signed .app) ---
APP="$ROOT/.build/ShortsCastMCP.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/shortscast-mcp" "$APP/Contents/MacOS/shortscast-mcp"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.shortscast.mcp</string>
  <key>CFBundleName</key><string>ShortsCastMCP</string>
  <key>CFBundleExecutable</key><string>shortscast-mcp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.3</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --deep --sign "$SIGN" "$APP"
echo "Built $APP"
echo "Grant it Screen Recording, Accessibility, Input Monitoring, then point your MCP client at:"
echo "  $APP/Contents/MacOS/shortscast-mcp"
```

- [ ] **Step 3: Build and bundle**

Run: `./Scripts/make-app.sh`
Expected: prints `Built …/ShortsCastMCP.app`.

- [ ] **Step 4: Grant permissions to the bundle (manual)**

Launch once so it registers with TCC, then grant in System Settings → Privacy & Security:
Run: `.build/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp </dev/null`
Add `ShortsCastMCP` under **Screen Recording**, **Accessibility**, and **Input Monitoring** (use the `+` and select `.build/ShortsCastMCP.app`).

- [ ] **Step 5: Live-verify the handshake + capture (manual)**

Feed a scripted session to the inner binary and confirm a real bundle is written:
```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"capture_test","arguments":{}}}' \
  | .build/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp
```
Expected: two JSON lines on stdout; the second's `content[0].text` contains `Wrote …spike-….shortscast, events=<n>`. Confirm the `.shortscast` dir exists and contains `raw.mov`, `events.json`, `meta.json`. If frames are missing (`noFramesCaptured`), the bundle/TCC path is wrong — stop and fix before proceeding.

- [ ] **Step 6: Remove the temporary capture_test tool**

Revert Step 1 (delete the `capture_test` entry) but keep `ping`. Keep the imports in `Server.swift` — later tasks use them.

Run: `swift build`
Expected: builds clean.

- [ ] **Step 7: Commit**

```bash
git add Scripts/make-app.sh Sources/ShortsCastMCP/Server.swift
git commit -m "chore(mcp): bundle ShortsCastMCP.app; verify signed-helper screen capture over stdio"
```

---

### Task 3: RecordingSessionStore actor + CaptureSession protocol

**Files:**
- Create: `Sources/ShortsCastMCP/CaptureSession.swift`
- Create: `Sources/ShortsCastMCP/RecordingSessionStore.swift`
- Test: `Tests/ShortsCastMCPTests/RecordingSessionStoreTests.swift`

**Interfaces:**
- Consumes: `Recorder.Result` (from `ShortsCastCapture`), `RecordingController`, `FocusSegment` (`ShortsCastCore`), `ProjectEdits` (`ShortsCastEditor`).
- Produces:
  - `protocol CaptureSessionProtocol { func start() async throws; func stop() async throws -> Recorder.Result }` and `extension RecordingController: CaptureSessionProtocol {}`.
  - `actor RecordingSessionStore` with:
    - `struct Active { let id: String; let startedAt: Date; let targetDesc: String; let bundleURL: URL; let session: CaptureSessionProtocol }`
    - `struct Entry { let bundleURL: URL; let createdISO: String; var duration: Double; var segments: [FocusSegment]; var edits: ProjectEdits }`
    - `enum StoreError: Error { case busy, idle, notFound }`
    - `func begin(_ active: Active) throws` — throws `.busy` if a session is active
    - `func end() async throws -> (Entry, Recorder.Result)` — throws `.idle` if none; calls `session.stop()`, builds/records an `Entry` (segments empty, default `ProjectEdits`), clears active
    - `func current() -> Active?`
    - `func register(_ entry: Entry)` / `func update(bundle: URL, mutate: (inout Entry) -> Void) throws`
    - `func recent() -> [Entry]` (most-recent first) / `func entry(for bundle: URL?) throws -> Entry` (defaults to most recent; throws `.notFound`)
    - a default `ProjectEdits` factory `static func defaultEdits() -> ProjectEdits`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ShortsCastMCPTests/RecordingSessionStoreTests.swift`:
```swift
import XCTest
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastMCP

final class FakeSession: CaptureSessionProtocol {
    let result: Recorder.Result
    init(_ url: URL) {
        result = Recorder.Result(bundleURL: url,
                                 eventLog: EventLog(duration: 3, screenSize: .init(width: 100, height: 100), events: []))
    }
    func start() async throws {}
    func stop() async throws -> Recorder.Result { result }
}

final class RecordingSessionStoreTests: XCTestCase {
    private func active(_ store: RecordingSessionStore, _ id: String, _ url: URL) -> RecordingSessionStore.Active {
        .init(id: id, startedAt: Date(), targetDesc: "display", bundleURL: url, session: FakeSession(url))
    }

    func test_beginTwice_throwsBusy() async throws {
        let store = RecordingSessionStore()
        let url = URL(fileURLWithPath: "/tmp/a.shortscast")
        try await store.begin(active(store, "s1", url))
        do { try await store.begin(active(store, "s2", url)); XCTFail("expected busy") }
        catch { XCTAssertEqual(error as? RecordingSessionStore.StoreError, .busy) }
    }

    func test_endWithoutBegin_throwsIdle() async {
        let store = RecordingSessionStore()
        do { _ = try await store.end(); XCTFail("expected idle") }
        catch { XCTAssertEqual(error as? RecordingSessionStore.StoreError, .idle) }
    }

    func test_beginEnd_recordsEntry_andClears() async throws {
        let store = RecordingSessionStore()
        let url = URL(fileURLWithPath: "/tmp/b.shortscast")
        try await store.begin(active(store, "s1", url))
        let (entry, result) = try await store.end()
        XCTAssertEqual(result.bundleURL, url)
        XCTAssertEqual(entry.duration, 3)
        let none = await store.current()
        XCTAssertNil(none)
        let recent = await store.recent()
        XCTAssertEqual(recent.first?.bundleURL, url)
    }

    func test_entryForNilBundle_defaultsToMostRecent() async throws {
        let store = RecordingSessionStore()
        let u1 = URL(fileURLWithPath: "/tmp/1.shortscast")
        let u2 = URL(fileURLWithPath: "/tmp/2.shortscast")
        try await store.begin(active(store, "s1", u1)); _ = try await store.end()
        try await store.begin(active(store, "s2", u2)); _ = try await store.end()
        let e = try await store.entry(for: nil)
        XCTAssertEqual(e.bundleURL, u2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RecordingSessionStoreTests`
Expected: FAIL — `CaptureSessionProtocol`, `RecordingSessionStore` undefined.

- [ ] **Step 3: Implement CaptureSession**

Create `Sources/ShortsCastMCP/CaptureSession.swift`:
```swift
import Foundation
import ShortsCastCapture

/// The recording behavior the store depends on. `RecordingController` conforms directly;
/// tests inject fakes so the store's state machine is testable without real capture.
public protocol CaptureSessionProtocol {
    func start() async throws
    func stop() async throws -> Recorder.Result
}

extension RecordingController: CaptureSessionProtocol {}
```

- [ ] **Step 4: Implement RecordingSessionStore**

Create `Sources/ShortsCastMCP/RecordingSessionStore.swift`:
```swift
import Foundation
import ShortsCastCore
import ShortsCastCapture
import ShortsCastRender
import ShortsCastEditor

public actor RecordingSessionStore {
    public struct Active {
        public let id: String
        public let startedAt: Date
        public let targetDesc: String
        public let bundleURL: URL
        public let session: CaptureSessionProtocol
        public init(id: String, startedAt: Date, targetDesc: String,
                    bundleURL: URL, session: CaptureSessionProtocol) {
            self.id = id; self.startedAt = startedAt; self.targetDesc = targetDesc
            self.bundleURL = bundleURL; self.session = session
        }
    }
    public struct Entry {
        public let bundleURL: URL
        public let createdISO: String
        public var duration: Double
        public var segments: [FocusSegment]
        public var edits: ProjectEdits
    }
    public enum StoreError: Error, Equatable { case busy, idle, notFound }

    private var active: Active?
    private var entries: [Entry] = []   // append order; most-recent = last

    public init() {}

    public static func defaultEdits() -> ProjectEdits {
        ProjectEdits(overrides: [], style: .default,
                     formatName: OutputFormat.vertical9x16.name, settings: AutoDirectorSettings())
    }

    public func begin(_ a: Active) throws {
        guard active == nil else { throw StoreError.busy }
        active = a
    }

    public func end() async throws -> (Entry, Recorder.Result) {
        guard let a = active else { throw StoreError.idle }
        let result = try await a.session.stop()
        active = nil
        let entry = Entry(bundleURL: a.bundleURL,
                          createdISO: ISO8601DateFormatter().string(from: a.startedAt),
                          duration: result.eventLog.duration, segments: [],
                          edits: Self.defaultEdits())
        entries.append(entry)
        return (entry, result)
    }

    public func current() -> Active? { active }
    public func register(_ entry: Entry) { entries.append(entry) }
    public func recent() -> [Entry] { entries.reversed() }

    public func entry(for bundle: URL?) throws -> Entry {
        if let bundle {
            guard let e = entries.last(where: { $0.bundleURL == bundle }) else { throw StoreError.notFound }
            return e
        }
        guard let e = entries.last else { throw StoreError.notFound }
        return e
    }

    public func update(bundle: URL, mutate: (inout Entry) -> Void) throws {
        guard let i = entries.lastIndex(where: { $0.bundleURL == bundle }) else { throw StoreError.notFound }
        mutate(&entries[i])
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter RecordingSessionStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortsCastMCP/CaptureSession.swift Sources/ShortsCastMCP/RecordingSessionStore.swift Tests/ShortsCastMCPTests/RecordingSessionStoreTests.swift
git commit -m "feat(mcp): RecordingSessionStore actor + CaptureSession protocol"
```

---

### Task 4: SessionPaths (default output dir + timestamped names)

**Files:**
- Create: `Sources/ShortsCastMCP/SessionPaths.swift`
- Test: `Tests/ShortsCastMCPTests/SessionPathsTests.swift`

**Interfaces:**
- Produces: `enum SessionPaths { static var outputDir: URL; static func bundleURL(at date: Date, dir: URL) -> URL; static func timestamp(_ date: Date) -> String }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ShortsCastMCPTests/SessionPathsTests.swift`:
```swift
import XCTest
@testable import ShortsCastMCP

final class SessionPathsTests: XCTestCase {
    func test_timestamp_isFilesystemSafe_andStable() {
        let d = Date(timeIntervalSince1970: 1_700_000_000) // fixed instant
        let ts = SessionPaths.timestamp(d)
        XCTAssertFalse(ts.contains(":"))
        XCTAssertFalse(ts.contains(" "))
        XCTAssertEqual(ts, SessionPaths.timestamp(d)) // deterministic
    }

    func test_bundleURL_hasShortscastExtension_inGivenDir() {
        let dir = URL(fileURLWithPath: "/tmp/out")
        let url = SessionPaths.bundleURL(at: Date(timeIntervalSince1970: 1_700_000_000), dir: dir)
        XCTAssertEqual(url.pathExtension, "shortscast")
        XCTAssertEqual(url.deletingLastPathComponent().path, "/tmp/out")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionPathsTests`
Expected: FAIL — `SessionPaths` undefined.

- [ ] **Step 3: Implement SessionPaths**

Create `Sources/ShortsCastMCP/SessionPaths.swift`:
```swift
import Foundation

public enum SessionPaths {
    /// Default: ~/Movies/ShortsCast (created on demand by callers).
    public static var outputDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Movies/ShortsCast", isDirectory: true)
    }

    /// A filesystem-safe timestamp like 2026-07-01_140233 (UTC), deterministic for a given instant.
    public static func timestamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        return fmt.string(from: date)
    }

    public static func bundleURL(at date: Date, dir: URL = SessionPaths.outputDir) -> URL {
        dir.appendingPathComponent("\(timestamp(date)).shortscast")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SessionPathsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastMCP/SessionPaths.swift Tests/ShortsCastMCPTests/SessionPathsTests.swift
git commit -m "feat(mcp): default output dir + timestamped bundle naming"
```

---

### Task 5: start_recording / stop_recording / recording_status

**Files:**
- Create: `Sources/ShortsCastMCP/StartArgs.swift`
- Create: `Sources/ShortsCastMCP/Handlers.swift`
- Test: `Tests/ShortsCastMCPTests/StartArgsTests.swift`
- Test: `Tests/ShortsCastMCPTests/HandlersLifecycleTests.swift`

**Interfaces:**
- Consumes: `RecordingSessionStore`, `TargetResolver`, `SessionPaths`, `Permissions`, `Director`, `AutoDirectorSettings`.
- Produces:
  - `struct StartArgs: Equatable { var displayIndex: Int?; var windowQuery: String?; var region: CGRect?; static func parse(_ args: JSONValue?) throws -> StartArgs }` and `enum StartArgError: Error, Equatable { case conflictingTargets, badRegion }`.
  - `struct Handlers { let store: RecordingSessionStore; ... }` with async methods returning `ToolResult`: `startRecording(_:)`, `stopRecording(_:)`, `recordingStatus(_:)`. Each method's first parameter is the tool's `JSONValue?` arguments.
  - `Handlers` gets a `makeSession: (ResolvedTarget, URL) -> CaptureSessionProtocol` factory (defaults to building a `RecordingController`) so lifecycle handlers are testable with fakes.

- [ ] **Step 1: Write the failing test for StartArgs**

Create `Tests/ShortsCastMCPTests/StartArgsTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import ShortsCastMCP

final class StartArgsTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    func test_empty_defaultsToMainDisplay() throws {
        let a = try StartArgs.parse(json("{}"))
        XCTAssertNil(a.displayIndex); XCTAssertNil(a.windowQuery); XCTAssertNil(a.region)
    }
    func test_windowName() throws {
        let a = try StartArgs.parse(json(#"{"target":"Google Chrome"}"#))
        XCTAssertEqual(a.windowQuery, "Google Chrome")
    }
    func test_display() throws {
        let a = try StartArgs.parse(json(#"{"display":1}"#))
        XCTAssertEqual(a.displayIndex, 1)
    }
    func test_region() throws {
        let a = try StartArgs.parse(json(#"{"region":{"x":10,"y":20,"w":640,"h":480}}"#))
        XCTAssertEqual(a.region, CGRect(x: 10, y: 20, width: 640, height: 480))
    }
    func test_conflict_throws() {
        XCTAssertThrowsError(try StartArgs.parse(json(#"{"target":"Safari","display":0}"#))) {
            XCTAssertEqual($0 as? StartArgError, .conflictingTargets)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StartArgsTests`
Expected: FAIL — `StartArgs` undefined.

- [ ] **Step 3: Implement StartArgs**

Create `Sources/ShortsCastMCP/StartArgs.swift`:
```swift
import Foundation
import CoreGraphics

public enum StartArgError: Error, Equatable { case conflictingTargets, badRegion }

/// Parses `start_recording` arguments into the mutually-exclusive target trio that
/// `TargetResolver.resolve` consumes. Mirrors CLIOptions' conflict rules.
public struct StartArgs: Equatable {
    public var displayIndex: Int?
    public var windowQuery: String?
    public var region: CGRect?

    public static func parse(_ args: JSONValue?) throws -> StartArgs {
        var out = StartArgs()
        if let t = args?["target"]?.stringValue, !t.isEmpty { out.windowQuery = t }
        if let d = args?["display"]?.intValue { out.displayIndex = d }
        if let r = args?["region"] {
            guard let x = r["x"]?.doubleValue, let y = r["y"]?.doubleValue,
                  let w = r["w"]?.doubleValue, let h = r["h"]?.doubleValue else {
                throw StartArgError.badRegion
            }
            out.region = CGRect(x: x, y: y, width: w, height: h)
        }
        let count = [out.displayIndex != nil, out.windowQuery != nil, out.region != nil].filter { $0 }.count
        if count > 1 { throw StartArgError.conflictingTargets }
        return out
    }
}
```

- [ ] **Step 4: Run StartArgs test to verify it passes**

Run: `swift test --filter StartArgsTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Write the failing lifecycle test**

Create `Tests/ShortsCastMCPTests/HandlersLifecycleTests.swift`:
```swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastMCP

final class HandlersLifecycleTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    private func makeHandlers(_ store: RecordingSessionStore) -> Handlers {
        Handlers(store: store, outputDir: URL(fileURLWithPath: NSTemporaryDirectory()),
                 requestPermissions: { }, permissionMissing: { [] },
                 resolveTarget: { _ in
                     ResolvedTarget(kind: "display", displayID: 0,
                                    captureRectPoints: CGRect(x: 0, y: 0, width: 100, height: 100),
                                    scale: 1, cropRect: nil)
                 },
                 makeSession: { _, url in FakeSession(url) })
    }

    func test_statusNone_thenStart_thenStatusActive_thenStop() async throws {
        let store = RecordingSessionStore()
        let h = makeHandlers(store)

        let s0 = await h.recordingStatus(nil)
        XCTAssertTrue(s0.text.contains("none"))

        let started = await h.startRecording(json("{}"))
        XCTAssertFalse(started.isError)
        XCTAssertTrue(started.text.contains("session"))

        let s1 = await h.recordingStatus(nil)
        XCTAssertTrue(s1.text.contains("display"))

        let stopped = await h.stopRecording(nil)
        XCTAssertFalse(stopped.isError)
        XCTAssertTrue(stopped.text.contains(".shortscast"))
    }

    func test_startWhileActive_isError() async throws {
        let store = RecordingSessionStore()
        let h = makeHandlers(store)
        _ = await h.startRecording(json("{}"))
        let again = await h.startRecording(json("{}"))
        XCTAssertTrue(again.isError)
        XCTAssertTrue(again.text.lowercased().contains("already"))
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `swift test --filter HandlersLifecycleTests`
Expected: FAIL — `Handlers` undefined.

- [ ] **Step 7: Implement Handlers (lifecycle methods)**

Create `Sources/ShortsCastMCP/Handlers.swift`:
```swift
import Foundation
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
import ShortsCastRender
import ShortsCastEditor

/// Binds tool arguments to library calls. All collaborators are injectable so handlers
/// are testable without real capture, permissions, or displays.
public struct Handlers {
    let store: RecordingSessionStore
    let outputDir: URL
    let requestPermissions: () -> Void
    let permissionMissing: () -> [String]
    let resolveTarget: (StartArgs) throws -> ResolvedTarget
    let makeSession: (ResolvedTarget, URL) -> CaptureSessionProtocol

    public init(store: RecordingSessionStore,
                outputDir: URL = SessionPaths.outputDir,
                requestPermissions: @escaping () -> Void = { Permissions.request() },
                permissionMissing: @escaping () -> [String] = { Permissions.status().missingNames },
                resolveTarget: @escaping (StartArgs) throws -> ResolvedTarget = { a in
                    try TargetResolver.resolve(displayIndex: a.displayIndex,
                                               windowQuery: a.windowQuery, region: a.region)
                },
                makeSession: @escaping (ResolvedTarget, URL) -> CaptureSessionProtocol = { target, url in
                    RecordingController(target: target, outBundle: url,
                                        appVersion: ShortsCastCapture.version,
                                        createdISO: ISO8601DateFormatter().string(from: Date()))
                }) {
        self.store = store; self.outputDir = outputDir
        self.requestPermissions = requestPermissions; self.permissionMissing = permissionMissing
        self.resolveTarget = resolveTarget; self.makeSession = makeSession
    }

    private func ok(_ v: JSONValue) -> ToolResult {
        let data = (try? JSONEncoder().encode(v)) ?? Data("{}".utf8)
        return ToolResult(text: String(data: data, encoding: .utf8) ?? "{}", isError: false)
    }
    private func err(_ message: String) -> ToolResult { ToolResult(text: message, isError: true) }

    public func startRecording(_ args: JSONValue?) async -> ToolResult {
        if await store.current() != nil { return err("A recording is already active. Stop it first.") }
        let parsed: StartArgs
        do { parsed = try StartArgs.parse(args) } catch { return err("Bad target: \(error)") }
        requestPermissions()
        let missing = permissionMissing()
        guard missing.isEmpty else { return err("Missing permissions: \(missing.joined(separator: ", "))") }
        do {
            let target = try resolveTarget(parsed)
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let startedAt = Date()
            let bundleURL = SessionPaths.bundleURL(at: startedAt, dir: outputDir)
            let session = makeSession(target, bundleURL)
            try await session.start()
            let id = UUID().uuidString
            try await store.begin(.init(id: id, startedAt: startedAt, targetDesc: target.kind,
                                        bundleURL: bundleURL, session: session))
            return ok(.object([
                "session_id": .string(id),
                "started_at": .string(ISO8601DateFormatter().string(from: startedAt)),
                "target": .string(target.kind),
                "bundle_path": .string(bundleURL.path)
            ]))
        } catch { return err("Could not start recording: \(error)") }
    }

    public func stopRecording(_ args: JSONValue?) async -> ToolResult {
        do {
            let (entry, result) = try await store.end()
            // Auto-direct once so segments are ready for list_segments/export.
            let dr = Director(settings: AutoDirectorSettings()).direct(log: result.eventLog, overrides: [])
            try? await store.update(bundle: entry.bundleURL) { $0.segments = dr.segments }
            return ok(.object([
                "bundle_path": .string(entry.bundleURL.path),
                "duration": .number(result.eventLog.duration),
                "event_count": .number(Double(result.eventLog.events.count)),
                "segment_count": .number(Double(dr.segments.count))
            ]))
        } catch RecordingSessionStore.StoreError.idle {
            return err("No active recording to stop.")
        } catch { return err("Stop failed: \(error)") }
    }

    public func recordingStatus(_ args: JSONValue?) async -> ToolResult {
        guard let a = await store.current() else { return ok(.object(["active": .string("none")])) }
        let elapsed = Date().timeIntervalSince(a.startedAt)
        return ok(.object([
            "session_id": .string(a.id),
            "elapsed": .number(elapsed),
            "target": .string(a.targetDesc)
        ]))
    }
}
```

- [ ] **Step 8: Run lifecycle test to verify it passes**

Run: `swift test --filter HandlersLifecycleTests`
Expected: PASS (2 tests).

- [ ] **Step 9: Commit**

```bash
git add Sources/ShortsCastMCP/StartArgs.swift Sources/ShortsCastMCP/Handlers.swift Tests/ShortsCastMCPTests/StartArgsTests.swift Tests/ShortsCastMCPTests/HandlersLifecycleTests.swift
git commit -m "feat(mcp): start/stop/status handlers with injectable capture + target resolution"
```

---

### Task 6: list_recordings

**Files:**
- Modify: `Sources/ShortsCastMCP/Handlers.swift`
- Test: `Tests/ShortsCastMCPTests/ListRecordingsTests.swift`

**Interfaces:**
- Produces: `Handlers.listRecordings(_ args: JSONValue?) async -> ToolResult` returning `{ "recordings": [ { "bundle_path", "created", "duration", "segment_count" } ] }` (most-recent first).

- [ ] **Step 1: Write the failing test**

Create `Tests/ShortsCastMCPTests/ListRecordingsTests.swift`:
```swift
import XCTest
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastMCP

final class ListRecordingsTests: XCTestCase {
    func test_listsMostRecentFirst() async throws {
        let store = RecordingSessionStore()
        let h = Handlers(store: store)
        for name in ["a", "b"] {
            let url = URL(fileURLWithPath: "/tmp/\(name).shortscast")
            await store.register(.init(bundleURL: url, createdISO: "2026-07-01T00:00:00Z",
                                       duration: 5, segments: [],
                                       edits: RecordingSessionStore.defaultEdits()))
        }
        let res = await h.listRecordings(nil)
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        let arr = v["recordings"]?.arrayValue
        XCTAssertEqual(arr?.count, 2)
        XCTAssertEqual(arr?.first?["bundle_path"]?.stringValue, "/tmp/b.shortscast")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ListRecordingsTests`
Expected: FAIL — `Handlers.listRecordings` undefined.

- [ ] **Step 3: Implement listRecordings**

Append to `Handlers` in `Sources/ShortsCastMCP/Handlers.swift`:
```swift
    public func listRecordings(_ args: JSONValue?) async -> ToolResult {
        let items = await store.recent().map { e in
            JSONValue.object([
                "bundle_path": .string(e.bundleURL.path),
                "created": .string(e.createdISO),
                "duration": .number(e.duration),
                "segment_count": .number(Double(e.segments.count))
            ])
        }
        return ok(.object(["recordings": .array(items)]))
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ListRecordingsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastMCP/Handlers.swift Tests/ShortsCastMCPTests/ListRecordingsTests.swift
git commit -m "feat(mcp): list_recordings handler"
```

---

### Task 7: Event-derived segment summary

**Files:**
- Create: `Sources/ShortsCastMCP/SegmentSummary.swift`
- Test: `Tests/ShortsCastMCPTests/SegmentSummaryTests.swift`

**Interfaces:**
- Consumes: `EventLog`, `RecordingEvent`, `FocusSegment`, `MouseButton` (`ShortsCastCore`).
- Produces: `enum SegmentSummary { static func describe(segment: FocusSegment, in log: EventLog) -> String }` — counts `click` (by button), `key`, `scroll` events in `[segment.start, segment.end)`; excludes `cursor`. Returns e.g. `"3 clicks (2 left, 1 right), 12 keystrokes, 1 scroll"` or `"no input"` when empty.

- [ ] **Step 1: Write the failing test**

Create `Tests/ShortsCastMCPTests/SegmentSummaryTests.swift`:
```swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastMCP

final class SegmentSummaryTests: XCTestCase {
    func test_countsWithinWindow_excludingCursor() {
        let log = EventLog(duration: 10, screenSize: .init(width: 100, height: 100), events: [
            .click(t: 1.0, point: .zero, button: .left),
            .click(t: 1.2, point: .zero, button: .left),
            .click(t: 1.4, point: .zero, button: .right),
            .key(t: 1.5), .key(t: 1.6),
            .scroll(t: 1.7, point: .zero, deltaY: 3),
            .cursor(t: 1.8, point: .zero),           // excluded
            .click(t: 5.0, point: .zero, button: .left) // outside window
        ])
        let seg = FocusSegment(start: 0.5, end: 2.0, center: .zero, zoom: 2)
        let s = SegmentSummary.describe(segment: seg, in: log)
        XCTAssertEqual(s, "3 clicks (2 left, 1 right), 2 keystrokes, 1 scroll")
    }

    func test_emptyWindow_saysNoInput() {
        let log = EventLog(duration: 10, screenSize: .init(width: 100, height: 100), events: [])
        let seg = FocusSegment(start: 0, end: 1, center: .zero, zoom: 2)
        XCTAssertEqual(SegmentSummary.describe(segment: seg, in: log), "no input")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SegmentSummaryTests`
Expected: FAIL — `SegmentSummary` undefined.

- [ ] **Step 3: Implement SegmentSummary**

Create `Sources/ShortsCastMCP/SegmentSummary.swift`:
```swift
import Foundation
import ShortsCastCore

/// Human-readable summary of the input events inside a focus segment's time window.
/// Pure MCP-layer glue over the recorded EventLog; no engine changes. Note: `key`
/// events carry no character, so keystrokes are reported as counts, never text.
public enum SegmentSummary {
    public static func describe(segment: FocusSegment, in log: EventLog) -> String {
        let inWindow = log.events.filter { $0.t >= segment.start && $0.t < segment.end }
        var left = 0, right = 0, otherClicks = 0, keys = 0, scrolls = 0
        for e in inWindow {
            switch e.type {
            case .click:
                switch e.button {
                case .left: left += 1
                case .right: right += 1
                default: otherClicks += 1
                }
            case .key: keys += 1
            case .scroll: scrolls += 1
            case .cursor: break
            }
        }
        let clicks = left + right + otherClicks
        var parts: [String] = []
        if clicks > 0 {
            var detail: [String] = []
            if left > 0 { detail.append("\(left) left") }
            if right > 0 { detail.append("\(right) right") }
            if otherClicks > 0 { detail.append("\(otherClicks) other") }
            parts.append("\(clicks) click\(clicks == 1 ? "" : "s") (\(detail.joined(separator: ", ")))")
        }
        if keys > 0 { parts.append("\(keys) keystroke\(keys == 1 ? "" : "s")") }
        if scrolls > 0 { parts.append("\(scrolls) scroll\(scrolls == 1 ? "" : "s")") }
        return parts.isEmpty ? "no input" : parts.joined(separator: ", ")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SegmentSummaryTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastMCP/SegmentSummary.swift Tests/ShortsCastMCPTests/SegmentSummaryTests.swift
git commit -m "feat(mcp): event-derived segment summaries"
```

---

### Task 8: list_segments

**Files:**
- Modify: `Sources/ShortsCastMCP/Handlers.swift`
- Test: `Tests/ShortsCastMCPTests/ListSegmentsTests.swift`

**Interfaces:**
- Consumes: `RecordingSessionStore.entry(for:)`, `ProjectBundle.read`, `SegmentSummary`.
- Produces: `Handlers.listSegments(_ args: JSONValue?) async -> ToolResult`. Reads the target bundle's `EventLog` (for summaries) and the entry's cached `segments`, returning `{ "bundle_path", "segments": [ { index, start, end, zoom, center:{x,y}, zoom_in_duration, zoom_out_duration, summary } ] }`. Ease-duration fields are `null` when the segment leaves them at the global default.
- Helper `segmentJSON(_ seg: FocusSegment, index: Int, summary: String) -> JSONValue` (reused by Task 9's drift response).

- [ ] **Step 1: Write the failing test**

Create `Tests/ShortsCastMCPTests/ListSegmentsTests.swift`:
```swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastMCP

final class ListSegmentsTests: XCTestCase {
    func test_listsSegmentsWithSummaries() async throws {
        // Write a real bundle so ProjectBundle.read works.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seg-\(UUID().uuidString).shortscast")
        let log = EventLog(duration: 4, screenSize: .init(width: 200, height: 200), events: [
            .click(t: 0.5, point: .zero, button: .left)
        ])
        let mov = tmp.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: mov.path, contents: Data([0, 1, 2]))
        defer { try? FileManager.default.removeItem(at: mov) }
        let meta = BundleMeta(targetKind: "display", displayID: 0, scale: 1,
                              captureRect: CGRect(x: 0, y: 0, width: 200, height: 200),
                              appVersion: "test", created: "2026-07-01T00:00:00Z")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: mov, to: tmp)

        let store = RecordingSessionStore()
        var edits = RecordingSessionStore.defaultEdits()
        let seg = FocusSegment(start: 0, end: 1, center: CGPoint(x: 50, y: 60), zoom: 2.5)
        await store.register(.init(bundleURL: tmp, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 4, segments: [seg], edits: edits))
        let h = Handlers(store: store)
        let res = await h.listSegments(nil)
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        let s0 = v["segments"]?.arrayValue?.first
        XCTAssertEqual(s0?["index"]?.intValue, 0)
        XCTAssertEqual(s0?["zoom"]?.doubleValue, 2.5)
        XCTAssertEqual(s0?["center"]?["x"]?.doubleValue, 50)
        XCTAssertEqual(s0?["summary"]?.stringValue, "1 click (1 left)")
        _ = edits
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ListSegmentsTests`
Expected: FAIL — `Handlers.listSegments` undefined.

- [ ] **Step 3: Implement listSegments + segmentJSON**

Append to `Handlers` in `Sources/ShortsCastMCP/Handlers.swift`:
```swift
    func segmentJSON(_ seg: FocusSegment, index: Int, summary: String) -> JSONValue {
        .object([
            "index": .number(Double(index)),
            "start": .number(seg.start),
            "end": .number(seg.end),
            "zoom": .number(Double(seg.zoom)),
            "center": .object(["x": .number(Double(seg.center.x)), "y": .number(Double(seg.center.y))]),
            "zoom_in_duration": seg.zoomInDuration.map { JSONValue.number($0) } ?? .null,
            "zoom_out_duration": seg.zoomOutDuration.map { JSONValue.number($0) } ?? .null,
            "summary": .string(summary)
        ])
    }

    private func bundleURL(from args: JSONValue?) -> URL? {
        args?["bundle"]?.stringValue.map { URL(fileURLWithPath: $0) }
    }

    public func listSegments(_ args: JSONValue?) async -> ToolResult {
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            let (log, _, _) = try ProjectBundle.read(entry.bundleURL)
            let segs = entry.segments.enumerated().map { i, seg in
                segmentJSON(seg, index: i, summary: SegmentSummary.describe(segment: seg, in: log))
            }
            return ok(.object(["bundle_path": .string(entry.bundleURL.path), "segments": .array(segs)]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording. Record something first, or pass a valid bundle path.")
        } catch { return err("Could not read segments: \(error)") }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ListSegmentsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ShortsCastMCP/Handlers.swift Tests/ShortsCastMCPTests/ListSegmentsTests.swift
git commit -m "feat(mcp): list_segments with event-derived summaries"
```

---

### Task 9: EditsStore + set_segment_camera

**Files:**
- Create: `Sources/ShortsCastMCP/EditsStore.swift`
- Modify: `Sources/ShortsCastMCP/Handlers.swift`
- Test: `Tests/ShortsCastMCPTests/EditsStoreTests.swift`
- Test: `Tests/ShortsCastMCPTests/SetSegmentCameraTests.swift`

**Interfaces:**
- Consumes: `ProjectEdits` (`ShortsCastEditor`), `upsertOverride`, `SegmentOverride` (`ShortsCastCore`).
- Produces:
  - `enum EditsStore { static func read(_ bundle: URL) -> ProjectEdits; static func write(_ edits: ProjectEdits, to bundle: URL) throws }` — persists as `project.json` inside the bundle; `read` returns `RecordingSessionStore.defaultEdits()` when absent.
  - `Handlers.setSegmentCamera(_ args: JSONValue?) async -> ToolResult` — applies `upsertOverride` into the entry's `ProjectEdits.overrides`, writes `project.json`, updates the cached entry, returns the updated override.

- [ ] **Step 1: Write the failing EditsStore test**

Create `Tests/ShortsCastMCPTests/EditsStoreTests.swift`:
```swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastEditor
@testable import ShortsCastMCP

final class EditsStoreTests: XCTestCase {
    func test_write_thenRead_roundTrips() throws {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edits-\(UUID().uuidString).shortscast")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }

        var edits = RecordingSessionStore.defaultEdits()
        edits.overrides = [SegmentOverride(index: 2, zoom: 3.0)]
        try EditsStore.write(edits, to: bundle)

        let back = EditsStore.read(bundle)
        XCTAssertEqual(back.overrides.first?.index, 2)
        XCTAssertEqual(back.overrides.first?.zoom, 3.0)
    }

    func test_read_missing_returnsDefaults() {
        let bundle = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).shortscast")
        XCTAssertEqual(EditsStore.read(bundle).overrides.count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EditsStoreTests`
Expected: FAIL — `EditsStore` undefined.

- [ ] **Step 3: Implement EditsStore**

Create `Sources/ShortsCastMCP/EditsStore.swift`:
```swift
import Foundation
import ShortsCastEditor

/// Reads/writes the bundle's project.json (ProjectEdits) — the same file the GUI editor
/// uses — so agent edits, export, and the app all agree.
public enum EditsStore {
    private static func url(_ bundle: URL) -> URL { bundle.appendingPathComponent("project.json") }

    public static func read(_ bundle: URL) -> ProjectEdits {
        guard let data = try? Data(contentsOf: url(bundle)),
              let edits = try? JSONDecoder().decode(ProjectEdits.self, from: data) else {
            return RecordingSessionStore.defaultEdits()
        }
        return edits
    }

    public static func write(_ edits: ProjectEdits, to bundle: URL) throws {
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(edits)
        try data.write(to: url(bundle))
    }
}
```

- [ ] **Step 4: Run EditsStore test to verify it passes**

Run: `swift test --filter EditsStoreTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Write the failing set_segment_camera test**

Create `Tests/ShortsCastMCPTests/SetSegmentCameraTests.swift`:
```swift
import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastMCP

final class SetSegmentCameraTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    func test_setsZoomAndPersists() async throws {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ssc-\(UUID().uuidString).shortscast")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }

        let store = RecordingSessionStore()
        let seg = FocusSegment(start: 0, end: 1, center: .zero, zoom: 2)
        await store.register(.init(bundleURL: bundle, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 2, segments: [seg], edits: RecordingSessionStore.defaultEdits()))
        let h = Handlers(store: store)

        let res = await h.setSegmentCamera(json(#"{"index":0,"zoom":2.8}"#))
        XCTAssertFalse(res.isError)
        // Persisted to project.json
        XCTAssertEqual(EditsStore.read(bundle).overrides.first?.zoom, 2.8)
        // Cached in the entry
        let e = try await store.entry(for: bundle)
        XCTAssertEqual(e.edits.overrides.first?.index, 0)
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `swift test --filter SetSegmentCameraTests`
Expected: FAIL — `Handlers.setSegmentCamera` undefined.

- [ ] **Step 7: Implement setSegmentCamera**

Append to `Handlers` in `Sources/ShortsCastMCP/Handlers.swift`:
```swift
    public func setSegmentCamera(_ args: JSONValue?) async -> ToolResult {
        guard let index = args?["index"]?.intValue else { return err("`index` is required.") }
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            var edits = entry.edits
            let zoom = args?["zoom"]?.doubleValue.map { CGFloat($0) }
            let center: CGPoint? = {
                guard let c = args?["center"], let x = c["x"]?.doubleValue, let y = c["y"]?.doubleValue else { return nil }
                return CGPoint(x: x, y: y)
            }()
            let zin = args?["zoom_in_duration"]?.doubleValue
            let zout = args?["zoom_out_duration"]?.doubleValue
            edits.overrides = upsertOverride(edits.overrides, index: index,
                                             zoom: zoom, center: center,
                                             zoomInDuration: zin, zoomOutDuration: zout)
            try EditsStore.write(edits, to: entry.bundleURL)
            try await store.update(bundle: entry.bundleURL) { $0.edits = edits }
            return ok(.object(["index": .number(Double(index)), "saved": .bool(true)]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Could not set segment camera: \(error)") }
    }
```

- [ ] **Step 8: Run test to verify it passes**

Run: `swift test --filter SetSegmentCameraTests`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/ShortsCastMCP/EditsStore.swift Sources/ShortsCastMCP/Handlers.swift Tests/ShortsCastMCPTests/EditsStoreTests.swift Tests/ShortsCastMCPTests/SetSegmentCameraTests.swift
git commit -m "feat(mcp): persist ProjectEdits to bundle; set_segment_camera"
```

---

### Task 10: SettingsPatch + set_director_settings + set_style

**Files:**
- Create: `Sources/ShortsCastMCP/SettingsPatch.swift`
- Modify: `Sources/ShortsCastMCP/Handlers.swift`
- Test: `Tests/ShortsCastMCPTests/SettingsPatchTests.swift`
- Test: `Tests/ShortsCastMCPTests/SetDirectorSettingsTests.swift`

**Interfaces:**
- Consumes: `AutoDirectorSettings`, `RenderStyle`, `Director`, `ProjectBundle.read`.
- Produces:
  - `enum SettingsPatch { static let resegmentingFields: Set<String>; static func isResegmenting(_ patchedKeys: [String]) -> Bool; static func apply(_ patch: JSONValue, to settings: AutoDirectorSettings) throws -> AutoDirectorSettings; static func apply(_ patch: JSONValue, to style: RenderStyle) throws -> RenderStyle; static func keys(_ patch: JSONValue?) -> [String] }`.
  - `Handlers.setDirectorSettings(_:) async -> ToolResult` and `Handlers.setStyle(_:) async -> ToolResult`.

**Note on patch semantics:** `AutoDirectorSettings` already decodes tolerantly (missing keys keep defaults), but a *partial patch* must preserve **existing** values, not fall back to type defaults. So `apply` merges by round-tripping the current value to a `[String: JSONValue]` object, overlaying the patch keys, then decoding back. `RenderStyle` has no tolerant decoder, so the same merge-then-decode approach is required for it too.

- [ ] **Step 1: Write the failing SettingsPatch test**

Create `Tests/ShortsCastMCPTests/SettingsPatchTests.swift`:
```swift
import XCTest
import ShortsCastCore
import ShortsCastRender
@testable import ShortsCastMCP

final class SettingsPatchTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    func test_apply_patchesOneField_preservesRest() throws {
        var settings = AutoDirectorSettings()
        settings.defaultZoom = 2.5
        let patched = try SettingsPatch.apply(json(#"{"zoomInDuration":0.9}"#), to: settings)
        XCTAssertEqual(patched.zoomInDuration, 0.9)
        XCTAssertEqual(patched.defaultZoom, 2.5) // untouched field preserved
    }

    func test_resegmentingClassification() {
        XCTAssertTrue(SettingsPatch.isResegmenting(["clusterTimeGap"]))
        XCTAssertTrue(SettingsPatch.isResegmenting(["defaultZoom", "clusterRadius"]))
        XCTAssertFalse(SettingsPatch.isResegmenting(["defaultZoom", "zoomInDuration"]))
    }

    func test_apply_style_patchesPadding() throws {
        let patched = try SettingsPatch.apply(json(#"{"paddingFraction":0.1}"#), to: RenderStyle.default)
        XCTAssertEqual(patched.paddingFraction, 0.1)
        XCTAssertEqual(patched.cornerRadius, RenderStyle.default.cornerRadius) // preserved
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsPatchTests`
Expected: FAIL — `SettingsPatch` undefined.

- [ ] **Step 3: Implement SettingsPatch**

Create `Sources/ShortsCastMCP/SettingsPatch.swift`:
```swift
import Foundation
import ShortsCastCore
import ShortsCastRender

/// Partial-patch merge for AutoDirectorSettings / RenderStyle, plus the classification of
/// which director fields change segmentation (and therefore may invalidate index-based
/// per-segment overrides).
public enum SettingsPatch {
    /// Director fields that affect how events cluster into segments (count/order).
    public static let resegmentingFields: Set<String> = [
        "clusterTimeGap", "clusterRadius", "dwellTime", "dwellRadius",
        "denseEventCount", "clickWeight", "keyWeight", "scrollWeight"
    ]

    public static func keys(_ patch: JSONValue?) -> [String] {
        guard case .object(let o)? = patch else { return [] }
        return Array(o.keys)
    }

    public static func isResegmenting(_ patchedKeys: [String]) -> Bool {
        patchedKeys.contains { resegmentingFields.contains($0) }
    }

    /// Merge `patch` onto `current` by overlaying keys on the object form, then decoding back.
    private static func merge<T: Codable>(_ patch: JSONValue, onto current: T) throws -> T {
        guard case .object(let patchObj) = patch else { return current }
        let base = try JSONValue.from(current)
        guard case .object(var obj) = base else { return current }
        for (k, v) in patchObj { obj[k] = v }
        return try JSONValue.object(obj).decoded(T.self)
    }

    public static func apply(_ patch: JSONValue, to settings: AutoDirectorSettings) throws -> AutoDirectorSettings {
        try merge(patch, onto: settings)
    }
    public static func apply(_ patch: JSONValue, to style: RenderStyle) throws -> RenderStyle {
        try merge(patch, onto: style)
    }
}
```

- [ ] **Step 4: Run SettingsPatch test to verify it passes**

Run: `swift test --filter SettingsPatchTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the failing set_director_settings test**

Create `Tests/ShortsCastMCPTests/SetDirectorSettingsTests.swift`:
```swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
@testable import ShortsCastMCP

final class SetDirectorSettingsTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    /// Writes a bundle with a few click events so the director produces segments.
    private func makeBundle() throws -> URL {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sds-\(UUID().uuidString).shortscast")
        let log = EventLog(duration: 10, screenSize: .init(width: 400, height: 400), events: [
            .click(t: 1, point: CGPoint(x: 50, y: 50), button: .left),
            .click(t: 6, point: CGPoint(x: 350, y: 350), button: .left)
        ])
        let mov = bundle.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: mov.path, contents: Data([0, 1, 2]))
        defer { try? FileManager.default.removeItem(at: mov) }
        let meta = BundleMeta(targetKind: "display", displayID: 0, scale: 1,
                              captureRect: CGRect(x: 0, y: 0, width: 400, height: 400),
                              appVersion: "test", created: "2026-07-01T00:00:00Z")
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: mov, to: bundle)
        return bundle
    }

    func test_safeField_reportsUnchangedSegments() async throws {
        let bundle = try makeBundle(); defer { try? FileManager.default.removeItem(at: bundle) }
        let store = RecordingSessionStore()
        await store.register(.init(bundleURL: bundle, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 10, segments: [], edits: RecordingSessionStore.defaultEdits()))
        let h = Handlers(store: store)
        let res = await h.setDirectorSettings(json(#"{"defaultZoom":3.0}"#))
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        XCTAssertEqual(v["segments_changed"]?.boolValue, false)
        XCTAssertEqual(EditsStore.read(bundle).settings.defaultZoom, 3.0)
    }

    func test_resegmentingField_returnsFreshSegments() async throws {
        let bundle = try makeBundle(); defer { try? FileManager.default.removeItem(at: bundle) }
        let store = RecordingSessionStore()
        await store.register(.init(bundleURL: bundle, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 10, segments: [], edits: RecordingSessionStore.defaultEdits()))
        let h = Handlers(store: store)
        let res = await h.setDirectorSettings(json(#"{"clusterTimeGap":0.1}"#))
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        XCTAssertEqual(v["segments_changed"]?.boolValue, true)
        XCTAssertNotNil(v["segments"]?.arrayValue)
        XCTAssertNotNil(v["old_segment_count"]?.intValue)
        XCTAssertNotNil(v["new_segment_count"]?.intValue)
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `swift test --filter SetDirectorSettingsTests`
Expected: FAIL — `Handlers.setDirectorSettings` undefined.

- [ ] **Step 7: Implement setDirectorSettings + setStyle**

Append to `Handlers` in `Sources/ShortsCastMCP/Handlers.swift`:
```swift
    public func setDirectorSettings(_ args: JSONValue?) async -> ToolResult {
        guard let patch = args, SettingsPatch.keys(args).contains(where: { $0 != "bundle" }) else {
            return err("Provide at least one AutoDirectorSettings field to patch.")
        }
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            var edits = entry.edits
            edits.settings = try SettingsPatch.apply(patch, to: edits.settings)
            try EditsStore.write(edits, to: entry.bundleURL)

            let patchedKeys = SettingsPatch.keys(args).filter { $0 != "bundle" }
            let resegmented = SettingsPatch.isResegmenting(patchedKeys)
            let oldCount = entry.segments.count

            if resegmented {
                let (log, _, _) = try ProjectBundle.read(entry.bundleURL)
                let dr = Director(settings: edits.settings).direct(log: log, overrides: [])
                try await store.update(bundle: entry.bundleURL) { $0.edits = edits; $0.segments = dr.segments }
                let segs = dr.segments.enumerated().map { i, seg in
                    segmentJSON(seg, index: i, summary: SegmentSummary.describe(segment: seg, in: log))
                }
                return ok(.object([
                    "segments_changed": .bool(true),
                    "old_segment_count": .number(Double(oldCount)),
                    "new_segment_count": .number(Double(dr.segments.count)),
                    "segments": .array(segs)
                ]))
            } else {
                try await store.update(bundle: entry.bundleURL) { $0.edits = edits }
                return ok(.object(["segments_changed": .bool(false),
                                   "new_segment_count": .number(Double(oldCount))]))
            }
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Could not set director settings: \(error)") }
    }

    public func setStyle(_ args: JSONValue?) async -> ToolResult {
        guard let patch = args, SettingsPatch.keys(args).contains(where: { $0 != "bundle" }) else {
            return err("Provide at least one RenderStyle field to patch.")
        }
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            var edits = entry.edits
            edits.style = try SettingsPatch.apply(patch, to: edits.style)
            try EditsStore.write(edits, to: entry.bundleURL)
            try await store.update(bundle: entry.bundleURL) { $0.edits = edits }
            return ok(.object(["saved": .bool(true)]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Could not set style: \(error)") }
    }
```

- [ ] **Step 8: Run test to verify it passes**

Run: `swift test --filter SetDirectorSettingsTests`
Expected: PASS (2 tests).

- [ ] **Step 9: Commit**

```bash
git add Sources/ShortsCastMCP/SettingsPatch.swift Sources/ShortsCastMCP/Handlers.swift Tests/ShortsCastMCPTests/SettingsPatchTests.swift Tests/ShortsCastMCPTests/SetDirectorSettingsTests.swift
git commit -m "feat(mcp): set_director_settings (with drift response) + set_style"
```

---

### Task 11: export_recording

**Files:**
- Modify: `Sources/ShortsCastMCP/Handlers.swift`
- Test: `Tests/ShortsCastMCPTests/ExportRecordingTests.swift`

**Interfaces:**
- Consumes: `EditsStore.read`, `ExportJob.run(bundleURL:formats:style:settings:outDir:overrides:)`, `OutputFormat.all`.
- Produces: `Handlers.exportRecording(_ args: JSONValue?) async -> ToolResult` returning `{ "mp4_paths": [ ... ] }`. Loads `ProjectEdits` from the bundle (`settings`, `style`, `overrides`) and passes them into `ExportJob.run`. `format` arg defaults to `9:16`; unknown format → error. Output dir defaults to the bundle's parent directory.

- [ ] **Step 1: Write the failing test**

Create `Tests/ShortsCastMCPTests/ExportRecordingTests.swift`. This test injects a fake exporter so it doesn't render real video:
```swift
import XCTest
import CoreGraphics
import ShortsCastCore
import ShortsCastRender
import ShortsCastCapture
@testable import ShortsCastMCP

final class ExportRecordingTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    func test_export_usesBundleEditsAndReturnsPaths() async throws {
        let bundle = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("exp-\(UUID().uuidString).shortscast")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }

        var edits = RecordingSessionStore.defaultEdits()
        edits.settings.defaultZoom = 3.0
        try EditsStore.write(edits, to: bundle)

        let store = RecordingSessionStore()
        await store.register(.init(bundleURL: bundle, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 5, segments: [], edits: edits))

        var captured: (formats: [OutputFormat], settings: AutoDirectorSettings)?
        let h = Handlers(store: store, export: { url, formats, style, settings, outDir, overrides in
            captured = (formats, settings)
            return formats.map { outDir.appendingPathComponent("out-\($0.name.replacingOccurrences(of: ":", with: "x")).mp4") }
        })

        let res = await h.exportRecording(json(#"{"format":"9:16"}"#))
        XCTAssertFalse(res.isError)
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(res.text.utf8))
        XCTAssertEqual(v["mp4_paths"]?.arrayValue?.count, 1)
        XCTAssertEqual(captured?.settings.defaultZoom, 3.0)      // loaded from project.json
        XCTAssertEqual(captured?.formats.first?.name, "9:16")
    }
}
```

- [ ] **Step 2: Add the injectable export closure to Handlers**

In `Handlers` (in `Sources/ShortsCastMCP/Handlers.swift`), add a stored property and init parameter:
```swift
    let export: (URL, [OutputFormat], RenderStyle, AutoDirectorSettings, URL, [SegmentOverride]) throws -> [URL]
```
Add to `init` parameter list (with a default that calls the real job):
```swift
                export: @escaping (URL, [OutputFormat], RenderStyle, AutoDirectorSettings, URL, [SegmentOverride]) throws -> [URL] = { url, formats, style, settings, outDir, overrides in
                    try ExportJob.run(bundleURL: url, formats: formats, style: style,
                                      settings: settings, outDir: outDir, overrides: overrides)
                },
```
and in the body assign `self.export = export`. (Place the parameter before `makeSession:` or after — order-independent since all are labeled; keep existing assignments intact.)

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ExportRecordingTests`
Expected: FAIL — `Handlers.exportRecording` undefined.

- [ ] **Step 4: Implement exportRecording**

Append to `Handlers`:
```swift
    public func exportRecording(_ args: JSONValue?) async -> ToolResult {
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            let formatName = args?["format"]?.stringValue ?? OutputFormat.vertical9x16.name
            guard let format = OutputFormat.all.first(where: { $0.name == formatName }) else {
                return err("Unknown format '\(formatName)'. Valid: \(OutputFormat.all.map { $0.name }.joined(separator: ", "))")
            }
            let edits = EditsStore.read(entry.bundleURL)
            let outDir = entry.bundleURL.deletingLastPathComponent()
            let urls = try export(entry.bundleURL, [format], edits.style, edits.settings, outDir, edits.overrides)
            return ok(.object(["mp4_paths": .array(urls.map { .string($0.path) })]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Export failed: \(error)") }
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ExportRecordingTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ShortsCastMCP/Handlers.swift Tests/ShortsCastMCPTests/ExportRecordingTests.swift
git commit -m "feat(mcp): export_recording honoring bundle ProjectEdits"
```

---

### Task 12: open_in_app + wire all tools into the server

**Files:**
- Create: `Sources/ShortsCastMCP/AppLauncher.swift`
- Modify: `Sources/ShortsCastMCP/Handlers.swift`
- Modify: `Sources/ShortsCastMCP/Server.swift` (real `allTools()` with schemas)
- Test: `Tests/ShortsCastMCPTests/OpenInAppTests.swift`
- Test: `Tests/ShortsCastMCPTests/ToolRegistryTests.swift`

**Interfaces:**
- Produces:
  - `Handlers.openInApp(_ args: JSONValue?) async -> ToolResult` — resolves the target bundle, invokes an injectable `launch: (URL) -> Bool`, returns `{ "opened": path }`. Default `launch` uses `NSWorkspace.shared.open`.
  - `ShortsCastMCP.allTools(handlers:) -> [MCPTool]` — the real 10-tool registry (name, description, JSON schema, handler). `allTools()` (no-arg) builds a `Handlers` with real defaults.

- [ ] **Step 1: Write the failing open_in_app test**

Create `Tests/ShortsCastMCPTests/OpenInAppTests.swift`:
```swift
import XCTest
import ShortsCastCapture
@testable import ShortsCastMCP

final class OpenInAppTests: XCTestCase {
    func test_open_invokesLauncherWithBundle() async throws {
        let bundle = URL(fileURLWithPath: "/tmp/open-\(UUID().uuidString).shortscast")
        let store = RecordingSessionStore()
        await store.register(.init(bundleURL: bundle, createdISO: "2026-07-01T00:00:00Z",
                                   duration: 1, segments: [], edits: RecordingSessionStore.defaultEdits()))
        var opened: URL?
        let h = Handlers(store: store, launch: { url in opened = url; return true })
        let res = await h.openInApp(nil)
        XCTAssertFalse(res.isError)
        XCTAssertEqual(opened, bundle)
    }
}
```

- [ ] **Step 2: Add the injectable launcher to Handlers**

In `Handlers`, add stored property + init parameter:
```swift
    let launch: (URL) -> Bool
```
init default:
```swift
                launch: @escaping (URL) -> Bool = { AppLauncher.open(bundle: $0) },
```
assign `self.launch = launch` in the body.

- [ ] **Step 3: Implement AppLauncher**

Create `Sources/ShortsCastMCP/AppLauncher.swift`:
```swift
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Opens a .shortscast bundle in the ShortsCast editor app. Best-effort: relies on the
/// bundle being associated with com.shortscast.app, else falls back to `open`.
public enum AppLauncher {
    public static func open(bundle: URL) -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.open(bundle)
        #else
        return false
        #endif
    }
}
```

- [ ] **Step 4: Implement openInApp**

Append to `Handlers`:
```swift
    public func openInApp(_ args: JSONValue?) async -> ToolResult {
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            let didOpen = launch(entry.bundleURL)
            guard didOpen else { return err("Could not open \(entry.bundleURL.path) in the app.") }
            return ok(.object(["opened": .string(entry.bundleURL.path)]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Open failed: \(error)") }
    }
```

- [ ] **Step 5: Run open_in_app test to verify it passes**

Run: `swift test --filter OpenInAppTests`
Expected: PASS.

- [ ] **Step 6: Write the failing tool-registry test**

Create `Tests/ShortsCastMCPTests/ToolRegistryTests.swift`:
```swift
import XCTest
@testable import ShortsCastMCP

final class ToolRegistryTests: XCTestCase {
    func test_allTools_exposesTenNamedTools() {
        let names = Set(ShortsCastMCP.allTools().map { $0.name })
        XCTAssertEqual(names, [
            "start_recording", "stop_recording", "recording_status", "list_recordings",
            "list_segments", "set_segment_camera", "set_director_settings", "set_style",
            "export_recording", "open_in_app"
        ])
    }

    func test_everyTool_hasObjectSchema() {
        for t in ShortsCastMCP.allTools() {
            XCTAssertEqual(t.inputSchema["type"]?.stringValue, "object", "\(t.name) schema")
        }
    }
}
```

- [ ] **Step 7: Run test to verify it fails**

Run: `swift test --filter ToolRegistryTests`
Expected: FAIL — `allTools()` still returns only the `ping` stub.

- [ ] **Step 8: Replace the stub allTools() with the real registry**

In `Sources/ShortsCastMCP/Server.swift`, replace the temporary `allTools()` extension with:
```swift
public extension ShortsCastMCP {
    static func allTools() -> [MCPTool] { allTools(handlers: Handlers(store: RecordingSessionStore())) }

    static func allTools(handlers h: Handlers) -> [MCPTool] {
        func obj(_ props: [String: JSONValue], required: [String] = []) -> JSONValue {
            var o: [String: JSONValue] = ["type": .string("object"), "properties": .object(props)]
            if !required.isEmpty { o["required"] = .array(required.map { .string($0) }) }
            return .object(o)
        }
        let str = JSONValue.object(["type": .string("string")])
        let num = JSONValue.object(["type": .string("number")])
        let int = JSONValue.object(["type": .string("integer")])
        let regionSchema = JSONValue.object([
            "type": .string("object"),
            "properties": .object(["x": num, "y": num, "w": num, "h": num])
        ])
        return [
            MCPTool(name: "start_recording",
                    description: "Start an open-ended screen recording. Target a window by app name (e.g. \"Google Chrome\"), a display index, or a screen region. One recording at a time.",
                    inputSchema: obj(["target": str, "display": int, "region": regionSchema])) { await h.startRecording($0) },
            MCPTool(name: "stop_recording",
                    description: "Stop the active recording, finalize the .shortscast bundle, and auto-direct it.",
                    inputSchema: obj(["session_id": str])) { await h.stopRecording($0) },
            MCPTool(name: "recording_status",
                    description: "Report whether a recording is active, its elapsed time and target.",
                    inputSchema: obj([:])) { await h.recordingStatus($0) },
            MCPTool(name: "list_recordings",
                    description: "List recent recordings (bundle path, created time, duration, segment count).",
                    inputSchema: obj([:])) { await h.listRecordings($0) },
            MCPTool(name: "list_segments",
                    description: "List a recording's auto-directed focus segments with an event-derived summary of each.",
                    inputSchema: obj(["bundle": str])) { await h.listSegments($0) },
            MCPTool(name: "set_segment_camera",
                    description: "Override a segment's camera: zoom, center {x,y}, and ease in/out durations.",
                    inputSchema: obj(["bundle": str, "index": int, "zoom": num,
                                      "center": regionSchema, "zoom_in_duration": num, "zoom_out_duration": num],
                                     required: ["index"])) { await h.setSegmentCamera($0) },
            MCPTool(name: "set_director_settings",
                    description: "Patch global auto-director settings (defaultZoom, zoomInDuration, restingAnchor, clusterTimeGap, …). Returns whether segments were re-cut.",
                    inputSchema: obj(["bundle": str, "defaultZoom": num, "maxZoom": num, "restingZoom": num,
                                      "zoomInDuration": num, "zoomOutDuration": num, "inactivityTimeout": num,
                                      "clusterTimeGap": num, "clusterRadius": num, "dwellTime": num,
                                      "dwellRadius": num, "dwellZoom": num, "denseEventCount": int,
                                      "clickWeight": num, "keyWeight": num, "scrollWeight": num,
                                      "zoomOutInPlace": .object(["type": .string("boolean")])])) { await h.setDirectorSettings($0) },
            MCPTool(name: "set_style",
                    description: "Patch render style (paddingFraction, cornerRadius, shadowOpacity, cursorRadius, …).",
                    inputSchema: obj(["bundle": str, "paddingFraction": num, "cornerRadius": num,
                                      "shadowOpacity": num, "shadowBlur": num, "shadowOffsetY": num,
                                      "cursorRadius": num, "rippleDuration": num, "rippleMaxRadius": num])) { await h.setStyle($0) },
            MCPTool(name: "export_recording",
                    description: "Export a finished mp4 for a recording, honoring its saved camera/settings/style. Defaults to vertical 9:16.",
                    inputSchema: obj(["bundle": str, "format": str])) { await h.exportRecording($0) },
            MCPTool(name: "open_in_app",
                    description: "Open a recording in the ShortsCast editor app for manual review.",
                    inputSchema: obj(["bundle": str])) { await h.openInApp($0) }
        ]
    }
}
```
Also delete the now-unused `capture_test`/`ping` imports only if unused; keep `import Foundation`, `import ShortsCastCapture`, `import ShortsCastCore` at the top of `Server.swift` (the extension references none directly, but leaving them is harmless — remove if the compiler warns about unused imports; Swift does not warn on unused imports, so leave them).

- [ ] **Step 9: Update main.swift to build a real shared Handlers**

The default `allTools()` builds a `Handlers` with a **fresh** store; the process needs ONE shared store across calls. Update `Sources/shortscast-mcp/main.swift`:
```swift
import Foundation
import ShortsCastMCP

// (StdioTransport as defined in Task 1 — unchanged)

let store = RecordingSessionStore()
let handlers = Handlers(store: store)
let transport = StdioTransport()
await ShortsCastMCP.serve(tools: ShortsCastMCP.allTools(handlers: handlers), transport: transport)
```

- [ ] **Step 10: Run the full test suite**

Run: `swift test`
Expected: PASS — all `ShortsCastMCPTests` plus the pre-existing suites (`swift test` runs everything; confirm no regressions).

- [ ] **Step 11: Commit**

```bash
git add Sources/ShortsCastMCP/AppLauncher.swift Sources/ShortsCastMCP/Handlers.swift Sources/ShortsCastMCP/Server.swift Sources/shortscast-mcp/main.swift Tests/ShortsCastMCPTests/OpenInAppTests.swift Tests/ShortsCastMCPTests/ToolRegistryTests.swift
git commit -m "feat(mcp): open_in_app + wire real 10-tool registry with a shared session store"
```

---

### Task 13: Packaging, client config, and live smoke test

**Files:**
- Modify: `Scripts/release.sh`
- Modify: `INSTALL.md`
- (make-app.sh already bundles the MCP app from Task 2)

**Interfaces:** None (packaging + docs). This task's deliverable is a working, granted MCP server registered in a client with all 10 tools listing.

- [ ] **Step 1: Ensure release.sh builds/signs the MCP helper**

Open `Scripts/release.sh`. If it invokes `make-app.sh` (which now also builds `ShortsCastMCP.app`), confirm the release zip includes `ShortsCastMCP.app`. If the zip is assembled from an explicit file list, add `ShortsCastMCP.app` alongside `ShortsCastRec.app` / `ShortsCastApp.app`. Make the minimal edit needed so `ShortsCastMCP.app` ships in the release artifact. (Read the script first; do not restructure it.)

- [ ] **Step 2: Document client config in INSTALL.md**

Append a section to `INSTALL.md`:
```markdown
## Agent (MCP) setup

ShortsCast ships an MCP server so Claude Desktop / Claude Code can record for you.
It must run as the signed app bundle so macOS grants it screen capture.

1. Build/sign the bundle: `./Scripts/make-app.sh` → produces `.build/ShortsCastMCP.app`.
   Move it somewhere stable, e.g. `~/Applications/ShortsCast/ShortsCastMCP.app`.
2. Grant it **Screen Recording**, **Accessibility**, and **Input Monitoring**
   (System Settings → Privacy & Security → add `ShortsCastMCP.app`).
3. Register the *inner* executable with your client:

   **Claude Desktop** — `~/Library/Application Support/Claude/claude_desktop_config.json`:
   ```json
   {
     "mcpServers": {
       "shortscast": {
         "command": "/Users/<you>/Applications/ShortsCast/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp"
       }
     }
   }
   ```

   **Claude Code**:
   ```
   claude mcp add shortscast /Users/<you>/Applications/ShortsCast/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp
   ```

4. Restart the client. Ask the agent to "start a recording of Google Chrome",
   do your task, then "stop and export". Files land in `~/Movies/ShortsCast/`.
```

- [ ] **Step 3: Live smoke test (manual)**

Register the server in Claude Code:
Run: `claude mcp add shortscast "$PWD/.build/ShortsCastMCP.app/Contents/MacOS/shortscast-mcp"`
Then in a Claude Code session confirm the client lists all 10 tools and `recording_status` returns "none". Then run a real loop: `start_recording` (target "Google Chrome") → wait a few seconds → `stop_recording` → `list_segments` → `export_recording`. Confirm an mp4 appears under `~/Movies/ShortsCast/` and plays.

- [ ] **Step 4: Commit**

```bash
git add Scripts/release.sh INSTALL.md
git commit -m "docs+release: ship ShortsCastMCP.app and document MCP client setup"
```

---

## Self-Review

**1. Spec coverage:**
- Architecture (`shortscast-mcp` exe + `ShortsCastMCP` lib, no SDK) → Tasks 1, 12. ✅
- Persistent stdio process / run loop → Task 1 (StdioTransport EOF loop), Task 2 (live-verified). ✅
- 10-tool surface → Tasks 5, 6, 8, 9, 10, 11, 12. ✅
- One-active-recording concurrency → Task 3 (`.busy`), Task 5 (start-while-active error). ✅
- Default output dir / vertical default → Tasks 4, 11. ✅
- Recording lifecycle & data flow → Tasks 3, 5, 8, 11. ✅
- Overrides persist into bundle project.json → Task 9. ✅
- Event-derived summary (counts, no text; cursor excluded) → Task 7. ✅
- Global tuning + precedence + index-drift classification/mitigation → Task 10. ✅
- TCC permissions spike sequenced early / signed .app requirement → Task 2. ✅
- Distribution + client config + smoke test → Tasks 2, 13. ✅
- Testing (glue + state machine + classification + summary + export wiring) → Tasks 1,3,5,7,8,9,10,11,12. ✅

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows real code and exact commands. ✅

**3. Type consistency:** `ToolResult(text:isError:)`, `MCPTool(name:description:inputSchema:handler:)`, `JSONValue` accessors, `RecordingSessionStore.Active/Entry/StoreError`, `CaptureSessionProtocol.start()/stop()->Recorder.Result`, `Handlers` injectable closures (`resolveTarget`, `makeSession`, `export`, `launch`), and `segmentJSON` (defined in Task 8, reused in Task 10) are consistent across tasks. `ExportJob.run(bundleURL:formats:style:settings:outDir:overrides:)` matches the real signature verified in the source. ✅
