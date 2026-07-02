import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Opens a .shortscast bundle in the ShortsCast editor app. Best-effort: relies on the
/// bundle being associated with com.shortscast.app, else falls back to `open`.
public enum AppLauncher {
    public static func open(bundle: URL) -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.open(bundle)
        #else
        return false
        #endif
    }
}
