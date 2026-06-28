import Foundation
import CoreGraphics

/// The raw, lossless metadata captured alongside the screen recording.
public struct EventLog: Codable, Equatable {
    public var duration: Seconds
    public var screenSize: CGSize
    public var events: [RecordingEvent]

    public init(duration: Seconds, screenSize: CGSize, events: [RecordingEvent]) {
        self.duration = duration
        self.screenSize = screenSize
        self.events = events
    }
}
