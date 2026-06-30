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

        /// Display names of the permissions that are not yet granted, in the order
        /// they appear in System Settings. Empty when `allGranted`.
        public var missingNames: [String] {
            var names: [String] = []
            if !screenRecording { names.append("Screen Recording") }
            if !accessibility { names.append("Accessibility") }
            if !inputMonitoring { names.append("Input Monitoring") }
            return names
        }
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
