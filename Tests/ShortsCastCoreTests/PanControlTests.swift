import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class PanControlTests: XCTestCase {
    private let screen = CGSize(width: 1920, height: 1080)

    func test_restingAnchor_offsetsRestingCenter() {
        var s = AutoDirectorSettings()
        s.restingAnchor = CGPoint(x: 0.25, y: 0.5)
        let path = AutoDirector(settings: s).cameraPath(segments: [], duration: 8, screenSize: screen)
        XCTAssertEqual(path.sample(at: 4).center.x, 1920 * 0.25, accuracy: 1e-6) // 480, not 960
    }

    func test_zoomOutInPlace_keepsSegmentCenterWhenZoomingOut() {
        var s = AutoDirectorSettings()
        s.zoomOutInPlace = true
        let seg = FocusSegment(start: 2.0, end: 2.5, center: CGPoint(x: 400, y: 300), zoom: 2.5)
        let path = AutoDirector(settings: s).cameraPath(segments: [seg], duration: 10, screenSize: screen)
        let after = path.sample(at: 2.5 + s.inactivityTimeout + s.zoomOutDuration + 0.5)
        XCTAssertEqual(after.scale, s.restingZoom, accuracy: 1e-6)      // zoomed back out
        XCTAssertEqual(after.center.x, 400, accuracy: 1e-6)            // stayed put, not recentered to 960
    }

    func test_defaultZoomOut_recentersToScreenCenter() {
        // Default (zoomOutInPlace == false) preserves the old behavior.
        let s = AutoDirectorSettings()
        let seg = FocusSegment(start: 2.0, end: 2.5, center: CGPoint(x: 400, y: 300), zoom: 2.5)
        let path = AutoDirector(settings: s).cameraPath(segments: [seg], duration: 10, screenSize: screen)
        let after = path.sample(at: 2.5 + s.inactivityTimeout + s.zoomOutDuration + 0.5)
        XCTAssertEqual(after.center.x, screen.width / 2, accuracy: 1e-6)
    }

    func test_settings_decodeToleratesMissingKeys() {
        // Older project.json lacks the new keys; decoding must fall back to defaults.
        let s = try! JSONDecoder().decode(AutoDirectorSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(s, AutoDirectorSettings())
        XCTAssertEqual(s.restingAnchor, CGPoint(x: 0.5, y: 0.5))
        XCTAssertFalse(s.zoomOutInPlace)
    }

    func test_settings_roundTripsNewKeys() {
        var s = AutoDirectorSettings()
        s.restingAnchor = CGPoint(x: 0.3, y: 0.7); s.zoomOutInPlace = true
        let back = try! JSONDecoder().decode(AutoDirectorSettings.self,
                                             from: try! JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func test_upsertOverride_mergesPreservingOtherField() {
        let base = [SegmentOverride(index: 1, center: CGPoint(x: 10, y: 20))]
        let merged = upsertOverride(base, index: 1, zoom: 3, center: nil)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].zoom, 3)
        XCTAssertEqual(merged[0].center, CGPoint(x: 10, y: 20)) // not clobbered
    }

    func test_upsertOverride_appendsWhenAbsent() {
        let merged = upsertOverride([], index: 2, zoom: nil, center: CGPoint(x: 5, y: 5))
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].index, 2)
        XCTAssertEqual(merged[0].center, CGPoint(x: 5, y: 5))
        XCTAssertNil(merged[0].zoom)
    }
}
