import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class OutputFormatTests: XCTestCase {
    func test_vertical_aspectRatio() {
        XCTAssertEqual(OutputFormat.vertical9x16.aspectRatio, 9.0/16.0, accuracy: 1e-6)
        XCTAssertEqual(OutputFormat.vertical9x16.exportSize, CGSize(width: 1080, height: 1920))
    }
    func test_all_containsFourPresets() {
        XCTAssertEqual(OutputFormat.all.count, 4)
    }
}
