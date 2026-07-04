import XCTest
@testable import ShortsCastMCP

final class ToolRegistryTests: XCTestCase {
    func test_allTools_exposesNamedTools() {
        let names = Set(ShortsCastMCP.allTools().map { $0.name })
        XCTAssertEqual(names, [
            "start_recording", "stop_recording", "recording_status", "list_recordings",
            "list_displays", "list_windows",
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
