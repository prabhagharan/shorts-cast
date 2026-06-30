// Sources/ShortsCastEditor/RecordingName.swift
import Foundation

/// Default file name for a new recording bundle. Embeds a timestamp so consecutive
/// recordings don't suggest the same name (and silently overwrite each other).
public enum RecordingName {
    public static func suggested(date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "recording-\(f.string(from: date)).shortscast"
    }
}
