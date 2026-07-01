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
