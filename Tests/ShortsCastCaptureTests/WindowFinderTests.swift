import XCTest
import CoreGraphics
@testable import ShortsCastCapture

final class WindowFinderTests: XCTestCase {
    private func win(owner: String, number: Int, bounds: [String: Any]?) -> [String: Any] {
        var d: [String: Any] = [kCGWindowOwnerName as String: owner, kCGWindowNumber as String: number]
        if let b = bounds { d[kCGWindowBounds as String] = b }
        return d
    }
    private let safariBounds: [String: Any] = ["X": 100, "Y": 50, "Width": 800, "Height": 600]

    func test_matchesByOwnerNameContains() {
        let list = [win(owner: "Finder", number: 1, bounds: ["X": 0, "Y": 0, "Width": 10, "Height": 10]),
                    win(owner: "Safari", number: 42, bounds: safariBounds)]
        let r = WindowFinder.selectBounds(in: list, matching: "saf")
        XCTAssertEqual(r, CGRect(x: 100, y: 50, width: 800, height: 600))
    }
    func test_matchesByWindowNumber() {
        let list = [win(owner: "Safari", number: 42, bounds: safariBounds)]
        XCTAssertEqual(WindowFinder.selectBounds(in: list, matching: "42"),
                       CGRect(x: 100, y: 50, width: 800, height: 600))
    }
    func test_noMatchReturnsNil() {
        let list = [win(owner: "Safari", number: 42, bounds: safariBounds)]
        XCTAssertNil(WindowFinder.selectBounds(in: list, matching: "Xcode"))
    }
    func test_matchButMissingBoundsReturnsNil() {
        let list = [win(owner: "Safari", number: 42, bounds: nil)]
        XCTAssertNil(WindowFinder.selectBounds(in: list, matching: "Safari"))
    }
}
