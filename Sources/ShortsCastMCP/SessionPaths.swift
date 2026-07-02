import Foundation

public enum SessionPaths {
    /// Default: ~/Movies/ShortsCast (created on demand by callers).
    public static var outputDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Movies/ShortsCast", isDirectory: true)
    }

    /// A filesystem-safe timestamp like 2026-07-01_140233 (UTC), deterministic for a given instant.
    public static func timestamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        return fmt.string(from: date)
    }

    public static func bundleURL(at date: Date, dir: URL = SessionPaths.outputDir) -> URL {
        dir.appendingPathComponent("\(timestamp(date)).shortscast")
    }
}
