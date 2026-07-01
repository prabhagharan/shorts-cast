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

public extension ShortsCastMCP {
    static func allTools() -> [MCPTool] {
        [ MCPTool(name: "ping", description: "Health check; returns pong.",
                  inputSchema: .object(["type": .string("object"), "properties": .object([:])])) { _ in
            ToolResult(text: "pong", isError: false) } ]
    }
}
