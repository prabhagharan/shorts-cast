import Foundation
import ShortsCastCore

/// Human-readable summary of the input events inside a focus segment's time window.
/// Pure MCP-layer glue over the recorded EventLog; no engine changes. Note: `key`
/// events carry no character, so keystrokes are reported as counts, never text.
public enum SegmentSummary {
    public static func describe(segment: FocusSegment, in log: EventLog) -> String {
        let inWindow = log.events.filter { $0.t >= segment.start && $0.t < segment.end }
        var left = 0, right = 0, otherClicks = 0, keys = 0, scrolls = 0
        for e in inWindow {
            switch e.type {
            case .click:
                switch e.button {
                case .left: left += 1
                case .right: right += 1
                default: otherClicks += 1
                }
            case .key: keys += 1
            case .scroll: scrolls += 1
            case .cursor: break
            }
        }
        let clicks = left + right + otherClicks
        var parts: [String] = []
        if clicks > 0 {
            var detail: [String] = []
            if left > 0 { detail.append("\(left) left") }
            if right > 0 { detail.append("\(right) right") }
            if otherClicks > 0 { detail.append("\(otherClicks) other") }
            parts.append("\(clicks) click\(clicks == 1 ? "" : "s") (\(detail.joined(separator: ", ")))")
        }
        if keys > 0 { parts.append("\(keys) keystroke\(keys == 1 ? "" : "s")") }
        if scrolls > 0 { parts.append("\(scrolls) scroll\(scrolls == 1 ? "" : "s")") }
        return parts.isEmpty ? "no input" : parts.joined(separator: ", ")
    }
}
