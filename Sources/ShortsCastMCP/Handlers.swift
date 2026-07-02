import Foundation
import CoreGraphics
import ShortsCastCore
import ShortsCastCapture
import ShortsCastRender
import ShortsCastEditor

/// Binds tool arguments to library calls. All collaborators are injectable so handlers
/// are testable without real capture, permissions, or displays.
public struct Handlers {
    let store: RecordingSessionStore
    let outputDir: URL
    let requestPermissions: () -> Void
    let permissionMissing: () -> [String]
    let resolveTarget: (StartArgs) throws -> ResolvedTarget
    let makeSession: (ResolvedTarget, URL) -> CaptureSessionProtocol

    public init(store: RecordingSessionStore,
                outputDir: URL = SessionPaths.outputDir,
                requestPermissions: @escaping () -> Void = { Permissions.request() },
                permissionMissing: @escaping () -> [String] = { Permissions.status().missingNames },
                resolveTarget: @escaping (StartArgs) throws -> ResolvedTarget = { a in
                    try TargetResolver.resolve(displayIndex: a.displayIndex,
                                               windowQuery: a.windowQuery, region: a.region)
                },
                makeSession: @escaping (ResolvedTarget, URL) -> CaptureSessionProtocol = { target, url in
                    RecordingController(target: target, outBundle: url,
                                        appVersion: ShortsCastCapture.version,
                                        createdISO: ISO8601DateFormatter().string(from: Date()))
                }) {
        self.store = store; self.outputDir = outputDir
        self.requestPermissions = requestPermissions; self.permissionMissing = permissionMissing
        self.resolveTarget = resolveTarget; self.makeSession = makeSession
    }

    private func ok(_ v: JSONValue) -> ToolResult {
        let data = (try? JSONEncoder().encode(v)) ?? Data("{}".utf8)
        return ToolResult(text: String(data: data, encoding: .utf8) ?? "{}", isError: false)
    }
    private func err(_ message: String) -> ToolResult { ToolResult(text: message, isError: true) }

    public func startRecording(_ args: JSONValue?) async -> ToolResult {
        if await store.current() != nil { return err("A recording is already active. Stop it first.") }
        let parsed: StartArgs
        do { parsed = try StartArgs.parse(args) } catch { return err("Bad target: \(error)") }
        requestPermissions()
        let missing = permissionMissing()
        guard missing.isEmpty else { return err("Missing permissions: \(missing.joined(separator: ", "))") }
        do {
            let target = try resolveTarget(parsed)
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
            let startedAt = Date()
            let bundleURL = SessionPaths.bundleURL(at: startedAt, dir: outputDir)
            let session = makeSession(target, bundleURL)
            try await session.start()
            let id = UUID().uuidString
            try await store.begin(.init(id: id, startedAt: startedAt, targetDesc: target.kind,
                                        bundleURL: bundleURL, session: session))
            return ok(.object([
                "session_id": .string(id),
                "started_at": .string(ISO8601DateFormatter().string(from: startedAt)),
                "target": .string(target.kind),
                "bundle_path": .string(bundleURL.path)
            ]))
        } catch { return err("Could not start recording: \(error)") }
    }

    public func stopRecording(_ args: JSONValue?) async -> ToolResult {
        do {
            let (entry, result) = try await store.end()
            // Auto-direct once so segments are ready for list_segments/export.
            let dr = Director(settings: AutoDirectorSettings()).direct(log: result.eventLog, overrides: [])
            try? await store.update(bundle: entry.bundleURL) { $0.segments = dr.segments }
            return ok(.object([
                "bundle_path": .string(entry.bundleURL.path),
                "duration": .number(result.eventLog.duration),
                "event_count": .number(Double(result.eventLog.events.count)),
                "segment_count": .number(Double(dr.segments.count))
            ]))
        } catch RecordingSessionStore.StoreError.idle {
            return err("No active recording to stop.")
        } catch { return err("Stop failed: \(error)") }
    }

    public func recordingStatus(_ args: JSONValue?) async -> ToolResult {
        guard let a = await store.current() else { return ok(.object(["active": .string("none")])) }
        let elapsed = Date().timeIntervalSince(a.startedAt)
        return ok(.object([
            "session_id": .string(a.id),
            "elapsed": .number(elapsed),
            "target": .string(a.targetDesc)
        ]))
    }
}
