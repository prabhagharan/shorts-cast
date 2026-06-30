import Foundation
import ShortsCastCore
import ShortsCastRender

/// The user's non-destructive edits, persisted as `project.json` inside a `.shortscast` bundle.
public struct ProjectEdits: Codable, Equatable {
    public var overrides: [SegmentOverride]
    public var style: RenderStyle
    public var formatName: String
    public var settings: AutoDirectorSettings
    public init(overrides: [SegmentOverride], style: RenderStyle,
                formatName: String, settings: AutoDirectorSettings) {
        self.overrides = overrides; self.style = style
        self.formatName = formatName; self.settings = settings
    }
}
