// Tests/ShortsCastRenderTests/ExportOptionsTests.swift
import XCTest
import ShortsCastCore
@testable import ShortsCastRender

final class ExportOptionsTests: XCTestCase {
    func test_parse_minimal() throws {
        let o = try ExportOptions.parse(["clip.shortscast", "--format", "9:16,1:1", "--out", "dir"])
        XCTAssertEqual(o.bundle, "clip.shortscast")
        XCTAssertEqual(o.formats, ["9:16", "1:1"])
        XCTAssertEqual(o.out, "dir")
        XCTAssertNil(o.stylePath)
    }
    func test_parse_missingOut_throws() {
        XCTAssertThrowsError(try ExportOptions.parse(["clip", "--format", "9:16"])) { err in
            XCTAssertEqual(err as? ExportParseError, .missingRequired("--out"))
        }
    }
    func test_parse_missingBundle_throws() {
        XCTAssertThrowsError(try ExportOptions.parse(["--format", "9:16", "--out", "d"])) { err in
            XCTAssertEqual(err as? ExportParseError, .missingRequired("bundle"))
        }
    }
    func test_resolveFormats_mapsNames() throws {
        let fmts = try ExportOptions.resolveFormats(["9:16", "16:9"])
        XCTAssertEqual(fmts.map { $0.name }, ["9:16", "16:9"])
    }
    func test_resolveFormats_unknownThrows() {
        XCTAssertThrowsError(try ExportOptions.resolveFormats(["9:16", "bogus"])) { err in
            XCTAssertEqual(err as? ExportParseError, .unknownFormat("bogus"))
        }
    }
}
