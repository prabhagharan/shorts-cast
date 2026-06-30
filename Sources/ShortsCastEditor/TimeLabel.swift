// Sources/ShortsCastEditor/TimeLabel.swift
import Foundation

/// Pure formatting: seconds -> "m:ss".
public enum TimeLabel {
    public static func format(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
