import XCTest
import CoreGraphics
@testable import ShortsCastCapture

final class WindowFinderOptionsTests: XCTestCase {
    private func win(number: Int, owner: String, name: String?, layer: Int,
                     w: CGFloat, h: CGFloat) -> [String: Any] {
        var d: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: number),
            kCGWindowOwnerName as String: owner,
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": w, "Height": h] as [String: Any]
        ]
        if let name = name { d[kCGWindowName as String] = name }
        return d
    }

    func test_keepsNormalAppWindowsAndBuildsLabels() {
        let list = [
            win(number: 42, owner: "Safari", name: "Apple", layer: 0, w: 800, h: 600),
            win(number: 7, owner: "Terminal", name: nil, layer: 0, w: 500, h: 400)
        ]
        let opts = WindowFinder.options(in: list)
        XCTAssertEqual(opts.map { $0.windowNumber }, [42, 7])
        XCTAssertEqual(opts[0].label, "Safari — Apple")
        XCTAssertEqual(opts[1].label, "Terminal") // empty title falls back to app name
    }

    func test_dropsMenubarTinyAndOwnerlessWindows() {
        let list = [
            win(number: 1, owner: "Menubar", name: "item", layer: 25, w: 200, h: 22),  // not layer 0
            win(number: 2, owner: "Dock", name: "", layer: 0, w: 10, h: 10),            // too small
            win(number: 3, owner: "", name: "ghost", layer: 0, w: 800, h: 600)          // no owner
        ]
        XCTAssertTrue(WindowFinder.options(in: list).isEmpty)
    }
}
