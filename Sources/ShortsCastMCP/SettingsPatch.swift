import Foundation
import ShortsCastCore
import ShortsCastRender

/// Partial-patch merge for AutoDirectorSettings / RenderStyle, plus the classification of
/// which director fields change segmentation (and therefore may invalidate index-based
/// per-segment overrides).
public enum SettingsPatch {
    /// Director fields that affect how events cluster into segments (count/order).
    public static let resegmentingFields: Set<String> = [
        "clusterTimeGap", "clusterRadius", "dwellTime", "dwellRadius",
        "denseEventCount", "clickWeight", "keyWeight", "scrollWeight"
    ]

    public static func keys(_ patch: JSONValue?) -> [String] {
        guard case .object(let o)? = patch else { return [] }
        return Array(o.keys)
    }

    public static func isResegmenting(_ patchedKeys: [String]) -> Bool {
        patchedKeys.contains { resegmentingFields.contains($0) }
    }

    /// Merge `patch` onto `current` by overlaying keys on the object form, then decoding back.
    private static func merge<T: Codable>(_ patch: JSONValue, onto current: T) throws -> T {
        guard case .object(let patchObj) = patch else { return current }
        let base = try JSONValue.from(current)
        guard case .object(var obj) = base else { return current }
        for (k, v) in patchObj { obj[k] = v }
        return try JSONValue.object(obj).decoded(T.self)
    }

    public static func apply(_ patch: JSONValue, to settings: AutoDirectorSettings) throws -> AutoDirectorSettings {
        try merge(patch, onto: settings)
    }
    public static func apply(_ patch: JSONValue, to style: RenderStyle) throws -> RenderStyle {
        try merge(patch, onto: style)
    }
}
