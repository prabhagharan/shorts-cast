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
