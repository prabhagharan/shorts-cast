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
