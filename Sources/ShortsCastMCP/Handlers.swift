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
    let export: (URL, [OutputFormat], RenderStyle, AutoDirectorSettings, URL, [SegmentOverride]) throws -> [URL]
    let launch: (URL) -> Bool

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
                },
                export: @escaping (URL, [OutputFormat], RenderStyle, AutoDirectorSettings, URL, [SegmentOverride]) throws -> [URL] = { url, formats, style, settings, outDir, overrides in
                    try ExportJob.run(bundleURL: url, formats: formats, style: style,
                                      settings: settings, outDir: outDir, overrides: overrides)
                },
                launch: @escaping (URL) -> Bool = { AppLauncher.open(bundle: $0) }) {
        self.store = store; self.outputDir = outputDir
        self.requestPermissions = requestPermissions; self.permissionMissing = permissionMissing
        self.resolveTarget = resolveTarget; self.makeSession = makeSession
        self.export = export; self.launch = launch
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

    private func recordingJSON(_ e: RecordingSessionStore.Entry) -> JSONValue {
        .object([
            "bundle_path": .string(e.bundleURL.path),
            "created": .string(e.createdISO),
            "duration": .number(e.duration),
            "segment_count": .number(Double(e.segments.count))
        ])
    }

    public func listRecordings(_ args: JSONValue?) async -> ToolResult {
        var seen = Set<String>()
        var items: [JSONValue] = []
        // In-memory entries first (most recent first).
        for e in await store.recent() where seen.insert(e.bundleURL.standardizedFileURL.path).inserted {
            items.append(recordingJSON(e))
        }
        // Disk scan of the output dir for bundles from earlier sessions. Timestamped names
        // sort newest-first lexicographically. entry(for:) reconstructs + caches each.
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil) {
            let bundles = contents.filter { $0.pathExtension == "shortscast" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for b in bundles where !seen.contains(b.standardizedFileURL.path) {
                if let e = try? await store.entry(for: b) {
                    seen.insert(b.standardizedFileURL.path)
                    items.append(recordingJSON(e))
                }
            }
        }
        return ok(.object(["recordings": .array(items)]))
    }

    func segmentJSON(_ seg: FocusSegment, index: Int, summary: String) -> JSONValue {
        .object([
            "index": .number(Double(index)),
            "start": .number(seg.start),
            "end": .number(seg.end),
            "zoom": .number(Double(seg.zoom)),
            "center": .object(["x": .number(Double(seg.center.x)), "y": .number(Double(seg.center.y))]),
            "zoom_in_duration": seg.zoomInDuration.map { JSONValue.number($0) } ?? .null,
            "zoom_out_duration": seg.zoomOutDuration.map { JSONValue.number($0) } ?? .null,
            "summary": .string(summary)
        ])
    }

    func bundleURL(from args: JSONValue?) -> URL? {
        args?["bundle"]?.stringValue.map { URL(fileURLWithPath: $0) }
    }

    public func listSegments(_ args: JSONValue?) async -> ToolResult {
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            let (log, _, _) = try ProjectBundle.read(entry.bundleURL)
            let segs = entry.segments.enumerated().map { i, seg in
                segmentJSON(seg, index: i, summary: SegmentSummary.describe(segment: seg, in: log))
            }
            return ok(.object(["bundle_path": .string(entry.bundleURL.path), "segments": .array(segs)]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording. Record something first, or pass a valid bundle path.")
        } catch { return err("Could not read segments: \(error)") }
    }

    public func setSegmentCamera(_ args: JSONValue?) async -> ToolResult {
        guard let index = args?["index"]?.intValue else { return err("`index` is required.") }
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            guard index >= 0 && index < entry.segments.count else {
                return err("Segment index \(index) out of range (0..<\(entry.segments.count)).")
            }
            var edits = entry.edits
            let zoom = args?["zoom"]?.doubleValue.map { CGFloat($0) }
            let center: CGPoint? = {
                guard let c = args?["center"], let x = c["x"]?.doubleValue, let y = c["y"]?.doubleValue else { return nil }
                return CGPoint(x: x, y: y)
            }()
            let zin = args?["zoom_in_duration"]?.doubleValue
            let zout = args?["zoom_out_duration"]?.doubleValue
            edits.overrides = upsertOverride(edits.overrides, index: index,
                                             zoom: zoom, center: center,
                                             zoomInDuration: zin, zoomOutDuration: zout)
            try EditsStore.write(edits, to: entry.bundleURL)
            try await store.update(bundle: entry.bundleURL) { $0.edits = edits }
            return ok(.object(["index": .number(Double(index)), "saved": .bool(true)]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Could not set segment camera: \(error)") }
    }

    public func setDirectorSettings(_ args: JSONValue?) async -> ToolResult {
        guard let patch = args, SettingsPatch.keys(args).contains(where: { $0 != "bundle" }) else {
            return err("Provide at least one AutoDirectorSettings field to patch.")
        }
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            var edits = entry.edits
            edits.settings = try SettingsPatch.apply(patch, to: edits.settings)
            try EditsStore.write(edits, to: entry.bundleURL)

            let patchedKeys = SettingsPatch.keys(args).filter { $0 != "bundle" }
            let resegmented = SettingsPatch.isResegmenting(patchedKeys)
            let oldCount = entry.segments.count

            if resegmented {
                let (log, _, _) = try ProjectBundle.read(entry.bundleURL)
                let dr = Director(settings: edits.settings).direct(log: log, overrides: [])
                try await store.update(bundle: entry.bundleURL) { $0.edits = edits; $0.segments = dr.segments }
                let segs = dr.segments.enumerated().map { i, seg in
                    segmentJSON(seg, index: i, summary: SegmentSummary.describe(segment: seg, in: log))
                }
                return ok(.object([
                    "segments_changed": .bool(true),
                    "old_segment_count": .number(Double(oldCount)),
                    "new_segment_count": .number(Double(dr.segments.count)),
                    "segments": .array(segs)
                ]))
            } else {
                try await store.update(bundle: entry.bundleURL) { $0.edits = edits }
                return ok(.object(["segments_changed": .bool(false),
                                   "new_segment_count": .number(Double(oldCount))]))
            }
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Could not set director settings: \(error)") }
    }

    public func setStyle(_ args: JSONValue?) async -> ToolResult {
        guard let patch = args, SettingsPatch.keys(args).contains(where: { $0 != "bundle" }) else {
            return err("Provide at least one RenderStyle field to patch.")
        }
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            var edits = entry.edits
            edits.style = try SettingsPatch.apply(patch, to: edits.style)
            try EditsStore.write(edits, to: entry.bundleURL)
            try await store.update(bundle: entry.bundleURL) { $0.edits = edits }
            return ok(.object(["saved": .bool(true)]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Could not set style: \(error)") }
    }

    public func exportRecording(_ args: JSONValue?) async -> ToolResult {
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            let formatName = args?["format"]?.stringValue ?? OutputFormat.vertical9x16.name
            guard let format = OutputFormat.all.first(where: { $0.name == formatName }) else {
                return err("Unknown format '\(formatName)'. Valid: \(OutputFormat.all.map { $0.name }.joined(separator: ", "))")
            }
            let edits = EditsStore.read(entry.bundleURL)
            let outDir = entry.bundleURL.deletingLastPathComponent()
            let urls = try export(entry.bundleURL, [format], edits.style, edits.settings, outDir, edits.overrides)
            return ok(.object(["mp4_paths": .array(urls.map { .string($0.path) })]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Export failed: \(error)") }
    }

    public func openInApp(_ args: JSONValue?) async -> ToolResult {
        do {
            let entry = try await store.entry(for: bundleURL(from: args))
            let didOpen = launch(entry.bundleURL)
            guard didOpen else { return err("Could not open \(entry.bundleURL.path) in the app.") }
            return ok(.object(["opened": .string(entry.bundleURL.path)]))
        } catch RecordingSessionStore.StoreError.notFound {
            return err("No such recording.")
        } catch { return err("Open failed: \(error)") }
    }
}
