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
