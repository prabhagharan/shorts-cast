// Tests/ShortsCastCaptureTests/CLIOptionsTests.swift
import XCTest
import CoreGraphics
@testable import ShortsCastCapture

final class CLIOptionsTests: XCTestCase {
    func test_parse_minimal_defaultsToMainDisplay() throws {
        let o = try CLIOptions.parse(["--seconds", "5", "--out", "a.shortscast"])
        XCTAssertEqual(o.seconds, 5, accuracy: 1e-9)
        XCTAssertEqual(o.out, "a.shortscast")
        XCTAssertNil(o.displayIndex); XCTAssertNil(o.windowQuery); XCTAssertNil(o.region)
        XCTAssertFalse(o.runDirect)
    }
    func test_parse_region_and_direct() throws {
        let o = try CLIOptions.parse(["--seconds", "3", "--out", "x", "--rect", "10,20,640,480", "--direct"])
        XCTAssertEqual(o.region, CGRect(x: 10, y: 20, width: 640, height: 480))
        XCTAssertTrue(o.runDirect)
    }
    func test_parse_missingSeconds_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(["--out", "x"])) { err in
            XCTAssertEqual(err as? CLIParseError, .missingRequired("--seconds"))
        }
    }
    func test_parse_conflictingTargets_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(
            ["--seconds", "1", "--out", "x", "--display", "0", "--window", "Safari"])) { err in
            XCTAssertEqual(err as? CLIParseError, .conflictingTargets)
        }
    }
    func test_parse_badRect_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(["--seconds", "1", "--out", "x", "--rect", "1,2,3"])) { err in
            XCTAssertEqual(err as? CLIParseError, .badValue("--rect"))
        }
    }
    func test_parse_missingOut_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(["--seconds", "5"])) { err in
            XCTAssertEqual(err as? CLIParseError, .missingRequired("--out"))
        }
    }

    func test_parse_unknownFlag_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(["--seconds", "5", "--out", "x", "--bogus"])) { err in
            XCTAssertEqual(err as? CLIParseError, .badValue("--bogus"))
        }
    }

    func test_parse_missingValueForFlag_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(["--seconds"])) { err in
            XCTAssertEqual(err as? CLIParseError, .badValue("--seconds"))
        }
    }

    func test_parse_nonPositiveSeconds_throws() {
        XCTAssertThrowsError(try CLIOptions.parse(["--seconds", "0", "--out", "x"])) { err in
            XCTAssertEqual(err as? CLIParseError, .badValue("--seconds"))
        }
    }
}
