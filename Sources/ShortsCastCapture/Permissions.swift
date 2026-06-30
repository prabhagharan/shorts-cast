import Foundation
import CoreGraphics
import ApplicationServices

public enum Permissions {
    public struct Status: Equatable {
        public var screenRecording: Bool
        public var accessibility: Bool
        public var inputMonitoring: Bool
        public init(screenRecording: Bool, accessibility: Bool, inputMonitoring: Bool) {
            self.screenRecording = screenRecording
            self.accessibility = accessibility
            self.inputMonitoring = inputMonitoring
        }
        public var allGranted: Bool { screenRecording && accessibility && inputMonitoring }
    }

    public static func status() -> Status {
        Status(screenRecording: CGPreflightScreenCaptureAccess(),
               accessibility: AXIsProcessTrusted(),
               inputMonitoring: CGPreflightListenEventAccess())
    }

    /// Prompts for any missing permission (no-ops if already granted).
    public static func request() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
    }
}
