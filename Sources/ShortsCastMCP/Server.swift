import Foundation
import ShortsCastCapture
import ShortsCastCore

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
