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
