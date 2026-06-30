// Sources/ShortsCastCapture/Recorder.swift
import Foundation
import CoreGraphics
import ShortsCastCore

public enum Recorder {
    public enum RecorderError: Error { case noFramesCaptured }
    public struct Result {
        public let bundleURL: URL
        public let eventLog: EventLog
    }

    /// Records `seconds` of the resolved target and writes a `.shortscast` bundle.
    /// Fixed-duration wrapper over `RecordingController` (start → wait → stop).
    public static func record(target: ResolvedTarget, seconds: Double, outBundle: URL,
                              appVersion: String, createdISO: String) async throws -> Result {
        let controller = RecordingController(target: target, outBundle: outBundle,
                                             appVersion: appVersion, createdISO: createdISO)
        try await controller.start()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return try await controller.stop()
    }
}
