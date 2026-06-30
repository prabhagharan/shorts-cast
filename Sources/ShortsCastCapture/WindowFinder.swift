import Foundation
import CoreGraphics

/// Pure selection over a CGWindowList-shaped array: find a window's on-screen bounds by
/// owner name (case-insensitive contains) or window number.
public enum WindowFinder {
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
