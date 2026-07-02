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
