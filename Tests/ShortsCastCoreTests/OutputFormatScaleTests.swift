import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class OutputFormatScaleTests: XCTestCase {
    func test_scaleByOneIsIdentity() {
        let f = OutputFormat.vertical9x16.scaled(by: 1)
        XCTAssertEqual(f.exportSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(f.name, "9:16")
    }
    func test_scaleByTwoDoublesDimensions() {
        let f = OutputFormat.vertical9x16.scaled(by: 2)
        XCTAssertEqual(f.exportSize, CGSize(width: 2160, height: 3840))
        XCTAssertEqual(f.aspectRatio, OutputFormat.vertical9x16.aspectRatio, accuracy: 1e-9)
    }
    func test_dimensionsAreAlwaysEven() {
        // 1350 * 1.5 = 2025 (odd) must round up to an even 2026 for H.264.
        let f = OutputFormat.portrait4x5.scaled(by: 1.5)
        XCTAssertEqual(Int(f.exportSize.width) % 2, 0)
        XCTAssertEqual(Int(f.exportSize.height) % 2, 0)
        XCTAssertEqual(f.exportSize.width, 1620, accuracy: 1e-9)
        XCTAssertEqual(f.exportSize.height, 2026, accuracy: 1e-9)
    }
}

final class VideoQualityTests: XCTestCase {
    func test_bitrateScalesWithPixelCount() {
        let small = VideoQuality.bitrate(width: 1080, height: 1920)
        let big = VideoQuality.bitrate(width: 2160, height: 3840)
        XCTAssertEqual(big, small * 4)          // 4x the pixels -> 4x the bits
        XCTAssertGreaterThan(small, 5_000_000)  // high quality: well above default
    }
}
