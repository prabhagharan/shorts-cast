// Sources/shortscast-rec/main.swift
import Foundation
import CoreGraphics
import ShortsCastCapture
import ShortsCastCore

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard #available(macOS 12.3, *) else {
    fail("shortscast-rec requires macOS 12.3 or later (ScreenCaptureKit).")
}

let options: CLIOptions
do {
    options = try CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("""
    Usage: shortscast-rec --seconds N --out path.shortscast \
    [--display N | --window <app-or-id> | --rect x,y,w,h] [--direct]
    Error: \(error)
    """)
}

Permissions.request()
let status = Permissions.status()
guard status.allGranted else {
    var msg = "Missing permissions. Enable in System Settings > Privacy & Security:\n"
    if !status.screenRecording { msg += "  • Screen Recording\n" }
    if !status.accessibility { msg += "  • Accessibility\n" }
    fail(msg)
}

let createdISO = ISO8601DateFormatter().string(from: Date())

// ScreenCaptureKit needs a live main run loop to deliver frames, so we must NOT
// block the main thread. Run the recording on a Task and keep the main run loop
// alive with CFRunLoopRun(); the Task calls exit() when done.
Task {
    // The top-level #available guard does not propagate into this async closure.
    guard #available(macOS 12.3, *) else { exit(1) }
    do {
        let target = try TargetResolver.resolve(
            displayIndex: options.displayIndex,
            windowQuery: options.windowQuery,
            region: options.region)
        let result = try await Recorder.record(
            target: target, seconds: options.seconds,
            outBundle: URL(fileURLWithPath: options.out),
            appVersion: ShortsCastCapture.version, createdISO: createdISO)
        print("Wrote \(result.bundleURL.path)")
        print("Events: \(result.eventLog.events.count), duration: \(String(format: "%.2f", result.eventLog.duration))s")
        if options.runDirect {
            let dr = Director(settings: AutoDirectorSettings())
                .direct(log: result.eventLog, overrides: [])
            print("Director: \(dr.segments.count) segments, \(dr.cameraPath.keyframes.count) keyframes")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Recording failed: \(error)\n".utf8))
        exit(2)
    }
}
CFRunLoopRun()
