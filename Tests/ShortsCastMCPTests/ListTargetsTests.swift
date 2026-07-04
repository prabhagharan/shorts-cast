import XCTest
@testable import ShortsCastCapture  // DisplayOption's memberwise init is internal
@testable import ShortsCastMCP

/// list_displays / list_windows expose the engine's target enumerators to agents so they
/// can discover a valid `display` index or window before calling start_recording. The
/// providers are injected so these run without real hardware.
final class ListTargetsTests: XCTestCase {
    private func decode(_ r: ToolResult) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(r.text.utf8))
    }

    func test_listDisplays_reportsIndexSizeAndMainFlag() async {
        let displays = [
            DisplayOption(index: 0, displayID: 1, isMain: true, pixelWidth: 2560, pixelHeight: 1600),
            DisplayOption(index: 1, displayID: 2, isMain: false, pixelWidth: 1920, pixelHeight: 1080)
        ]
        let h = Handlers(store: RecordingSessionStore(), listDisplaysProvider: { displays })
        let res = await h.listDisplays(nil)
        XCTAssertFalse(res.isError)
        let v = decode(res)
        let arr = v["displays"]?.arrayValue ?? []
        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr[0]["index"]?.intValue, 0)
        XCTAssertEqual(arr[0]["width"]?.intValue, 2560)
        XCTAssertEqual(arr[0]["height"]?.intValue, 1600)
        XCTAssertEqual(arr[0]["is_main"]?.boolValue, true)
        XCTAssertEqual(arr[1]["index"]?.intValue, 1)
        XCTAssertEqual(arr[1]["is_main"]?.boolValue, false)
        // A human-readable label agents can echo back to the user.
        XCTAssertEqual(arr[0]["label"]?.stringValue, "Display 1 (2560×1600) — Main")
    }

    func test_listWindows_reportsAppTitleAndQuery() async {
        let windows = [
            WindowOption(windowNumber: 42, appName: "Google Chrome", title: "GitHub"),
            WindowOption(windowNumber: 7, appName: "Terminal", title: "")
        ]
        let h = Handlers(store: RecordingSessionStore(), listWindowsProvider: { windows })
        let res = await h.listWindows(nil)
        XCTAssertFalse(res.isError)
        let v = decode(res)
        let arr = v["windows"]?.arrayValue ?? []
        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr[0]["app"]?.stringValue, "Google Chrome")
        XCTAssertEqual(arr[0]["title"]?.stringValue, "GitHub")
        // windowNumber (as a string) is an exact `target` for start_recording.
        XCTAssertEqual(arr[0]["target"]?.stringValue, "42")
        XCTAssertEqual(arr[0]["label"]?.stringValue, "Google Chrome — GitHub")
        // Empty title falls back to the app name in the label.
        XCTAssertEqual(arr[1]["label"]?.stringValue, "Terminal")
    }

    func test_listDisplays_emptyWhenNoneReported() async {
        let h = Handlers(store: RecordingSessionStore(), listDisplaysProvider: { [] })
        let res = await h.listDisplays(nil)
        XCTAssertFalse(res.isError)
        XCTAssertEqual(decode(res)["displays"]?.arrayValue?.count, 0)
    }
}
