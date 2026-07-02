import XCTest
import CoreGraphics
@testable import ShortsCastMCP

final class StartArgsTests: XCTestCase {
    private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    func test_empty_defaultsToMainDisplay() throws {
        let a = try StartArgs.parse(json("{}"))
        XCTAssertNil(a.displayIndex); XCTAssertNil(a.windowQuery); XCTAssertNil(a.region)
    }
    func test_windowName() throws {
        let a = try StartArgs.parse(json(#"{"target":"Google Chrome"}"#))
        XCTAssertEqual(a.windowQuery, "Google Chrome")
    }
    func test_display() throws {
        let a = try StartArgs.parse(json(#"{"display":1}"#))
        XCTAssertEqual(a.displayIndex, 1)
    }
    func test_region() throws {
        let a = try StartArgs.parse(json(#"{"region":{"x":10,"y":20,"w":640,"h":480}}"#))
        XCTAssertEqual(a.region, CGRect(x: 10, y: 20, width: 640, height: 480))
    }
    func test_conflict_throws() {
        XCTAssertThrowsError(try StartArgs.parse(json(#"{"target":"Safari","display":0}"#))) {
            XCTAssertEqual($0 as? StartArgError, .conflictingTargets)
        }
    }
}
