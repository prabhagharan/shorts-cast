import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class VirtualCameraTests: XCTestCase {
    private let screen = CGSize(width: 1920, height: 1080)

    func test_baseCrop_vertical_isLimitedByHeight() {
        let base = VirtualCamera.baseCropSize(screen: screen, format: .vertical9x16)
        XCTAssertEqual(base.height, 1080, accuracy: 1e-6)
        XCTAssertEqual(base.width, 1080 * 9.0 / 16.0, accuracy: 1e-6) // 607.5
    }

    func test_baseCrop_landscapeMatchingScreen_isFullScreen() {
        let base = VirtualCamera.baseCropSize(screen: screen, format: .landscape16x9)
        XCTAssertEqual(base.width, 1920, accuracy: 1e-6)
        XCTAssertEqual(base.height, 1080, accuracy: 1e-6)
    }

    func test_restingVerticalCrop_isCentered() {
        let rect = VirtualCamera.cropRect(
            state: CameraState(center: CGPoint(x: 960, y: 540), scale: 1),
            format: .vertical9x16, screen: screen)
        XCTAssertEqual(rect.width, 607.5, accuracy: 1e-3)
        XCTAssertEqual(rect.height, 1080, accuracy: 1e-6)
        XCTAssertEqual(rect.midX, 960, accuracy: 1e-3)
    }

    func test_zoomedCrop_shrinksAndCentersOnPoint() {
        let rect = VirtualCamera.cropRect(
            state: CameraState(center: CGPoint(x: 500, y: 400), scale: 2),
            format: .vertical9x16, screen: screen)
        XCTAssertEqual(rect.width, 607.5 / 2, accuracy: 1e-3)
        XCTAssertEqual(rect.height, 540, accuracy: 1e-6)
        XCTAssertEqual(rect.midX, 500, accuracy: 1e-3)
        XCTAssertEqual(rect.midY, 400, accuracy: 1e-3)
    }

    func test_cropNearEdge_isClampedInsideScreen() {
        let rect = VirtualCamera.cropRect(
            state: CameraState(center: CGPoint(x: 0, y: 0), scale: 2),
            format: .vertical9x16, screen: screen)
        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, screen.width + 1e-6)
        XCTAssertLessThanOrEqual(rect.maxY, screen.height + 1e-6)
    }
}
