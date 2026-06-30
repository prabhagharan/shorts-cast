import Foundation
import CoreGraphics

/// A user-pickable on-screen window. `windowNumber` resolves exactly via
/// `TargetResolver.resolve(windowQuery:)`.
public struct WindowOption: Equatable {
    public let windowNumber: Int
    public let appName: String
    public let title: String
    public init(windowNumber: Int, appName: String, title: String) {
        self.windowNumber = windowNumber; self.appName = appName; self.title = title
    }
    public var label: String { title.isEmpty ? appName : "\(appName) — \(title)" }
}

/// Pure selection over a CGWindowList-shaped array: find a window's on-screen bounds by
/// owner name (case-insensitive contains) or window number.
public enum WindowFinder {
    /// Pure transform of a CGWindowList into pickable options: keep normal app windows
    /// (layer 0) with a named owner and a non-trivial size; drop menubar/overlay/system chrome.
    public static func options(in windows: [[String: Any]]) -> [WindowOption] {
        windows.compactMap { w -> WindowOption? in
            guard let number = (w[kCGWindowNumber as String] as? NSNumber)?.intValue,
                  let owner = w[kCGWindowOwnerName as String] as? String, !owner.isEmpty,
                  let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let bounds = boundsRect(w[kCGWindowBounds as String]),
                  bounds.width >= 40, bounds.height >= 40 else { return nil }
            let title = (w[kCGWindowName as String] as? String) ?? ""
            return WindowOption(windowNumber: number, appName: owner, title: title)
        }
    }

    public static func selectBounds(in windows: [[String: Any]], matching query: String) -> CGRect? {
        for w in windows {
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            let numberMatches = (w[kCGWindowNumber as String] as? NSNumber).map { "\($0.intValue)" == query } ?? false
            guard owner.localizedCaseInsensitiveContains(query) || numberMatches else { continue }
            if let rect = boundsRect(w[kCGWindowBounds as String]) { return rect }
        }
        return nil
    }

    private static func boundsRect(_ any: Any?) -> CGRect? {
        guard let d = any as? [String: Any] else { return nil }
        func num(_ k: String) -> CGFloat? { (d[k] as? NSNumber).map { CGFloat(truncating: $0) } }
        guard let x = num("X"), let y = num("Y"), let w = num("Width"), let h = num("Height") else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
