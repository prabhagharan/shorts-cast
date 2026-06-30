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
    public static func record(target: ResolvedTarget, seconds: Double, outBundle: URL,
                              appVersion: String, createdISO: String) async throws -> Result {
        let geometry = CaptureGeometry(captureRect: target.captureRectPoints, scale: target.scale)
        let builder = EventLogBuilder(geometry: geometry, cursorHz: 60)
        let tap = EventTap { builder.add($0) }
        tap.start()

        let tmpMov = FileManager.default.temporaryDirectory
            .appendingPathComponent("shortscast-\(UUID().uuidString).mov")
        let session = AVScreenCaptureSession(outputURL: tmpMov, displayID: target.displayID,
                                             cropRect: target.cropRect, pixelSize: geometry.pixelSize)
        try await session.start()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        let times = await session.stop()
        tap.stop()

        defer { try? FileManager.default.removeItem(at: tmpMov) }
        if let writerError = session.writerError { throw writerError }
        guard session.firstFramePTSSeconds != nil else { throw RecorderError.noFramesCaptured }

        let log = builder.build(firstFrameT: times.firstFrameT, endT: times.endT)
        let meta = BundleMeta(targetKind: target.kind, displayID: target.displayID,
                              scale: Double(target.scale), captureRect: target.captureRectPoints,
                              appVersion: appVersion, created: createdISO)
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: tmpMov, to: outBundle)
        return Result(bundleURL: outBundle, eventLog: log)
    }
}
