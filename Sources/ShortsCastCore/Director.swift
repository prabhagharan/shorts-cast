import Foundation
import CoreGraphics

/// The full output of directing one recording.
public struct DirectorResult: Equatable {
    public var segments: [FocusSegment]
    public var cameraPath: CameraPath
    public var cursor: CursorTrack
    public init(segments: [FocusSegment], cameraPath: CameraPath, cursor: CursorTrack) {
        self.segments = segments; self.cameraPath = cameraPath; self.cursor = cursor
    }
}

/// Single entry point: EventLog (+ manual overrides) -> camera path + cursor track.
public struct Director {
    public var settings: AutoDirectorSettings
    public init(settings: AutoDirectorSettings) { self.settings = settings }

    public func direct(log: EventLog, overrides: [SegmentOverride]) -> DirectorResult {
        let clustered = EventClusterer(settings: settings).segments(from: log)
        let dwell = DwellDetector(settings: settings).segments(from: log)
        let combined = mergeNonOverlapping(primary: clustered, secondary: dwell)
        let segments = applyOverrides(combined, overrides)
        let path = AutoDirector(settings: settings)
            .cameraPath(segments: segments, duration: log.duration, screenSize: log.screenSize)
        let cursor = CursorTrackBuilder(smoother: SpringSmoother()).build(from: log)
        return DirectorResult(segments: segments, cameraPath: path, cursor: cursor)
    }

    public func cropRect(_ result: DirectorResult,
                         at t: Seconds,
                         format: OutputFormat,
                         screen: CGSize) -> CGRect {
        let state = result.cameraPath.sample(at: t)
        return VirtualCamera.cropRect(state: state, format: format, screen: screen)
    }
}
