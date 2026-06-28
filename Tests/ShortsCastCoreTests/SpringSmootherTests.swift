import XCTest
import CoreGraphics
@testable import ShortsCastCore

final class SpringSmootherTests: XCTestCase {
    func test_convergesTowardConstantTarget() {
        // A step input: jump to (100,0) and hold; smoothed output should approach it.
        var samples: [TimedPoint] = [TimedPoint(t: 0, p: .zero)]
        var t = 0.0
        for _ in 0..<120 { t += 1.0/60.0; samples.append(TimedPoint(t: t, p: CGPoint(x: 100, y: 0))) }
        let out = SpringSmoother(frequency: 6).smooth(samples)
        XCTAssertEqual(out.count, samples.count)
        XCTAssertEqual(out.first!.p, .zero)            // first sample preserved
        XCTAssertEqual(Double(out.last!.p.x), 100, accuracy: 1.0) // converged
    }

    func test_criticallyDamped_doesNotOvershootMuch() {
        var samples: [TimedPoint] = [TimedPoint(t: 0, p: .zero)]
        var t = 0.0
        for _ in 0..<120 { t += 1.0/60.0; samples.append(TimedPoint(t: t, p: CGPoint(x: 100, y: 0))) }
        let out = SpringSmoother(frequency: 6).smooth(samples)
        let maxX = out.map { Double($0.p.x) }.max() ?? 0
        XCTAssertLessThan(maxX, 105) // critical damping → negligible overshoot
    }

    func test_emptyInput_returnsEmpty() {
        XCTAssertTrue(SpringSmoother().smooth([]).isEmpty)
    }
}
