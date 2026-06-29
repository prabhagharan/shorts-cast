import Foundation
import CoreGraphics
import ShortsCastCore

public struct BundleMeta: Codable, Equatable {
    public var targetKind: String      // "display" | "window" | "region"
    public var displayID: UInt32?
    public var scale: Double
    public var captureRect: CGRect     // global points
    public var appVersion: String
    public var created: String         // ISO8601, supplied by the caller
    public init(targetKind: String, displayID: UInt32?, scale: Double,
                captureRect: CGRect, appVersion: String, created: String) {
        self.targetKind = targetKind; self.displayID = displayID; self.scale = scale
        self.captureRect = captureRect; self.appVersion = appVersion; self.created = created
    }
}

public enum ProjectBundle {
    public enum BundleError: Error { case rawVideoMissing }

    public static func write(eventLog: EventLog, meta: BundleMeta,
                             rawVideo: URL, to bundleURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rawVideo.path) else { throw BundleError.rawVideoMissing }
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try fm.copyItem(at: rawVideo, to: bundleURL.appendingPathComponent("raw.mov"))
        let enc = JSONEncoder()
        try enc.encode(eventLog).write(to: bundleURL.appendingPathComponent("events.json"))
        try enc.encode(meta).write(to: bundleURL.appendingPathComponent("meta.json"))
    }

    public static func read(_ bundleURL: URL) throws
        -> (eventLog: EventLog, meta: BundleMeta, rawVideoURL: URL) {
        let dec = JSONDecoder()
        let log = try dec.decode(EventLog.self,
            from: Data(contentsOf: bundleURL.appendingPathComponent("events.json")))
        let meta = try dec.decode(BundleMeta.self,
            from: Data(contentsOf: bundleURL.appendingPathComponent("meta.json")))
        return (log, meta, bundleURL.appendingPathComponent("raw.mov"))
    }
}
