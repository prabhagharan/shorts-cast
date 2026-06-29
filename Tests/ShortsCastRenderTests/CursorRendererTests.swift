import XCTest
import CoreGraphics
import ShortsCastCore
@testable import ShortsCastRender

final class CursorRendererTests: XCTestCase {
    func test_position_nilWhenEmpty() {
        XCTAssertNil(CursorRenderer.position(at: 1, samples: []))
    }
    func test_position_clampsAndInterpolates() {
        let s = [TimedPoint(t: 0, p: CGPoint(x: 0, y: 0)),
                 TimedPoint(t: 2, p: CGPoint(x: 100, y: 0))]
        XCTAssertEqual(CursorRenderer.position(at: -1, samples: s), CGPoint(x: 0, y: 0))   // clamp start
        XCTAssertEqual(CursorRenderer.position(at: 9, samples: s), CGPoint(x: 100, y: 0))  // clamp end
        let mid = CursorRenderer.position(at: 1, samples: s)!
        XCTAssertEqual(mid.x, 50, accuracy: 1e-6)                                          // linear midpoint
    }
    func test_activeRipples_windowAndProgress() {
        let clicks = [ClickRipple(t: 1.0, point: CGPoint(x: 10, y: 10)),
                      ClickRipple(t: 5.0, point: CGPoint(x: 20, y: 20))]
        let active = CursorRenderer.activeRipples(at: 1.25, clicks: clicks, duration: 0.5)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active[0].point, CGPoint(x: 10, y: 10))
        XCTAssertEqual(active[0].progress, 0.5, accuracy: 1e-6) // (1.25-1.0)/0.5
    }
    func test_activeRipples_excludesOutOfWindow() {
        let clicks = [ClickRipple(t: 1.0, point: .zero)]
        XCTAssertTrue(CursorRenderer.activeRipples(at: 2.0, clicks: clicks, duration: 0.5).isEmpty)
    }
}
