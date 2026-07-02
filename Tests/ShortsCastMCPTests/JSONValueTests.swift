import XCTest
@testable import ShortsCastMCP

final class JSONValueTests: XCTestCase {
    func test_roundTrip_object() throws {
        let json = #"{"a":1,"b":"x","c":[true,null]}"#
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(v["a"]?.doubleValue, 1)
        XCTAssertEqual(v["b"]?.stringValue, "x")
        XCTAssertEqual(v["c"]?.arrayValue?.first?.boolValue, true)
        let reEncoded = try JSONEncoder().encode(v)
        let back = try JSONDecoder().decode(JSONValue.self, from: reEncoded)
        XCTAssertEqual(v, back)
    }

    struct Point: Codable, Equatable { var x: Double; var y: Double }

    func test_decoded_intoCodable() throws {
        let v = try JSONValue.from(Point(x: 3, y: 4))
        XCTAssertEqual(try v.decoded(Point.self), Point(x: 3, y: 4))
    }

    func test_intValue_fromWholeNumber() throws {
        let v = try JSONDecoder().decode(JSONValue.self, from: Data("7".utf8))
        XCTAssertEqual(v.intValue, 7)
    }
}
