import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class ZoomSpeedTests: XCTestCase {
    private let screen = CGSize(width: 1920, height: 1080)

    func test_perSegmentZoomInDuration_slowsTheRamp() {
        let fast = FocusSegment(start: 2, end: 5, center: CGPoint(x: 400, y: 300), zoom: 2.5) // global in = 0.4
        var slow = fast; slow.zoomInDuration = 1.2
        let s = AutoDirectorSettings()
        let pFast = AutoDirector(settings: s).cameraPath(segments: [fast], duration: 10, screenSize: screen)
        let pSlow = AutoDirector(settings: s).cameraPath(segments: [slow], duration: 10, screenSize: screen)
        // At start + global 0.4s: fast is fully zoomed; slow is only partway in.
        XCTAssertEqual(pFast.sample(at: 2.4).scale, 2.5, accuracy: 1e-6)
        XCTAssertLessThan(pSlow.sample(at: 2.4).scale, 2.5)
    }

    func test_applyOverrides_setsDurations() {
        let segs = [FocusSegment(start: 0, end: 1, center: .zero, zoom: 2)]
        let out = applyOverrides(segs, [SegmentOverride(index: 0, zoomInDuration: 0.9, zoomOutDuration: 1.1)])
        XCTAssertEqual(out[0].zoomInDuration, 0.9)
        XCTAssertEqual(out[0].zoomOutDuration, 1.1)
    }

    func test_upsertOverride_preservesDurationsWhenEditingZoom() {
        let base = [SegmentOverride(index: 0, zoomInDuration: 0.9)]
        let merged = upsertOverride(base, index: 0, zoom: 3, center: nil)
        XCTAssertEqual(merged[0].zoom, 3)
        XCTAssertEqual(merged[0].zoomInDuration, 0.9) // not clobbered
    }

    func test_segmentOverride_codableToleratesMissingDurationKeys() {
        let o = try! JSONDecoder().decode(SegmentOverride.self, from: Data("{\"index\":0,\"zoom\":3}".utf8))
        XCTAssertEqual(o.index, 0)
        XCTAssertEqual(o.zoom, 3)
        XCTAssertNil(o.zoomInDuration)
        XCTAssertNil(o.zoomOutDuration)
    }
}
