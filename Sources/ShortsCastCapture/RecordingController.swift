// Sources/ShortsCastCapture/RecordingController.swift
import Foundation
import CoreGraphics
import ShortsCastCore

/// A start/stop recording session: begins capturing the display and input events on
/// `start()` and keeps going until `stop()`, which finalizes the `.shortscast` bundle.
/// Use this for open-ended "record until I stop" capture; `Recorder.record(seconds:)`
/// wraps it for fixed-duration capture.
public final class RecordingController {
    private let target: ResolvedTarget
    private let outBundle: URL
    private let appVersion: String
    private let createdISO: String
    private let builder: EventLogBuilder
    private let tap: EventTap
    private let session: AVScreenCaptureSession
    private let tmpMov: URL

    public init(target: ResolvedTarget, outBundle: URL, appVersion: String,
                createdISO: String, cursorHz: Double = 60) {
        self.target = target
        self.outBundle = outBundle
        self.appVersion = appVersion
        self.createdISO = createdISO
        let geometry = CaptureGeometry(captureRect: target.captureRectPoints, scale: target.scale)
        let builder = EventLogBuilder(geometry: geometry, cursorHz: cursorHz)
        self.builder = builder
        self.tap = EventTap { builder.add($0) }
        self.tmpMov = FileManager.default.temporaryDirectory
            .appendingPathComponent("shortscast-\(UUID().uuidString).mov")
        self.session = AVScreenCaptureSession(outputURL: tmpMov, displayID: target.displayID,
                                              cropRect: target.cropRect, pixelSize: geometry.pixelSize)
    }

    public func start() async throws {
        tap.start()
        try await session.start()
    }

    /// Stops capture, writes the bundle, and returns the result. Cleans up the temp file.
    public func stop() async throws -> Recorder.Result {
        let times = await session.stop()
        tap.stop()
        defer { try? FileManager.default.removeItem(at: tmpMov) }
        if let writerError = session.writerError { throw writerError }
        guard session.firstFramePTSSeconds != nil else { throw Recorder.RecorderError.noFramesCaptured }

        let log = builder.build(firstFrameT: times.firstFrameT, endT: times.endT)
        let meta = BundleMeta(targetKind: target.kind, displayID: target.displayID,
                              scale: Double(target.scale), captureRect: target.captureRectPoints,
                              appVersion: appVersion, created: createdISO)
        try ProjectBundle.write(eventLog: log, meta: meta, rawVideo: tmpMov, to: outBundle)
        return Recorder.Result(bundleURL: outBundle, eventLog: log)
    }
}
