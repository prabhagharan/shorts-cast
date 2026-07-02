import Foundation
import ShortsCastCapture

/// The recording behavior the store depends on. `RecordingController` conforms directly;
/// tests inject fakes so the store's state machine is testable without real capture.
public protocol CaptureSessionProtocol {
    func start() async throws
    func stop() async throws -> Recorder.Result
}

extension RecordingController: CaptureSessionProtocol {}
