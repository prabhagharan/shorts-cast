// Tests/ShortsCastEditorTests/PlaybackClockTests.swift
import XCTest
@testable import ShortsCastEditor

final class PlaybackClockTests: XCTestCase {
    func test_advancesByWallClockElapsed() {
        // Started playing at preview time 2.0 when the wall clock read 100.0.
        // 0.5s of wall time later, the preview should be at 2.5 — independent of
        // how many render ticks happened in between.
        let r = PlaybackClock.tick(startWall: 100.0, startTime: 2.0, nowWall: 100.5, duration: 10)
        XCTAssertEqual(r.time, 2.5, accuracy: 1e-9)
        XCTAssertTrue(r.playing)
    }
    func test_slowRendersDoNotSlowPlayback() {
        // Even if only one tick fires after 3s of wall time, the clock jumps ahead
        // (frames are skipped, not slowed).
        let r = PlaybackClock.tick(startWall: 0, startTime: 0, nowWall: 3.0, duration: 10)
        XCTAssertEqual(r.time, 3.0, accuracy: 1e-9)
    }
    func test_clampsAndStopsAtDuration() {
        let r = PlaybackClock.tick(startWall: 0, startTime: 9.5, nowWall: 1.0, duration: 10)
        XCTAssertEqual(r.time, 10, accuracy: 1e-9)
        XCTAssertFalse(r.playing)
    }
}
