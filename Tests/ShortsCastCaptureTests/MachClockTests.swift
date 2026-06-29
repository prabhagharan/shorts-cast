import XCTest
@testable import ShortsCastCapture

final class MachClockTests: XCTestCase {
    func test_identityTimebase_nanosToSeconds() {
        // numer/denom = 1/1 → ticks are nanoseconds
        XCTAssertEqual(machTicksToSeconds(1_000_000_000, numer: 1, denom: 1), 1.0, accuracy: 1e-12)
    }
    func test_scaledTimebase() {
        // numer/denom = 125/3 (a real Apple-silicon-style ratio): 24,000,000 ticks
        // → 24e6 * 125/3 ns = 1.0e9 ns = 1.0 s
        XCTAssertEqual(machTicksToSeconds(24_000_000, numer: 125, denom: 3), 1.0, accuracy: 1e-9)
    }
}
