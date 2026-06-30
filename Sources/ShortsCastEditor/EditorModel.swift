// Sources/ShortsCastEditor/EditorModel.swift
import Foundation
import Combine
import CoreGraphics
import CoreImage
import ShortsCastCore
import ShortsCastCapture
import ShortsCastRender

public final class EditorModel: ObservableObject {
    public enum EditorError: Error { case notOpen }

    @Published public private(set) var bundleURL: URL?
    @Published public private(set) var eventLog: EventLog?
    @Published public private(set) var rawVideoURL: URL?
    @Published public private(set) var screenSize: CGSize = .zero { didSet { if !isLoading { invalidateCompositor() } } }
    @Published public private(set) var overrides: [SegmentOverride] = []
    @Published public private(set) var result: DirectorResult?
    @Published public var selectedSegment: Int?

    @Published public var settings = AutoDirectorSettings() { didSet { if !isLoading { regenerate() } } }
    @Published public var style = RenderStyle.default { didSet { if !isLoading { invalidateCompositor() } } }
    @Published public var format = OutputFormat.vertical9x16 { didSet { if !isLoading { invalidateCompositor() } } }

    var frameSource: FrameSource?          // settable for tests
    private var cachedCompositor: FrameCompositor?
    private var isLoading = false

    public init() {}

    public var segments: [FocusSegment] { result?.segments ?? [] }
    public var duration: Seconds { eventLog?.duration ?? 0 }

    public func open(_ url: URL) throws {
        let (log, _, raw) = try ProjectBundle.read(url)
        isLoading = true
        selectedSegment = nil
        bundleURL = url
        eventLog = log
        rawVideoURL = raw
        screenSize = log.screenSize
        if let edits = loadEdits(from: url) {
            overrides = edits.overrides
            settings = edits.settings
            style = edits.style
            format = OutputFormat.all.first { $0.name == edits.formatName } ?? .vertical9x16
        } else {
            overrides = []
            settings = AutoDirectorSettings()
            style = .default
            format = .vertical9x16
        }
        frameSource = AVAssetFrameSource(url: raw)
        cachedCompositor = nil
        isLoading = false
        regenerate()
    }

    private func regenerate() {
        guard let log = eventLog else { return }
        result = Director(settings: settings).direct(log: log, overrides: overrides)
    }

    public func setZoom(segment index: Int, zoom: CGFloat) {
        overrides = upsertOverride(overrides, index: index, zoom: zoom, center: nil)
        regenerate()
    }

    /// Overrides where the given segment focuses (pan target), in screen pixels.
    public func setCenter(segment index: Int, center: CGPoint) {
        overrides = upsertOverride(overrides, index: index, zoom: nil, center: center)
        regenerate()
    }

    /// Overrides this segment's ease-in / ease-out durations (seconds).
    public func setZoomInDuration(segment index: Int, duration: Double) {
        overrides = upsertOverride(overrides, index: index, zoomInDuration: duration)
        regenerate()
    }
    public func setZoomOutDuration(segment index: Int, duration: Double) {
        overrides = upsertOverride(overrides, index: index, zoomOutDuration: duration)
        regenerate()
    }

    public func clearOverride(segment index: Int) {
        overrides.removeAll { $0.index == index }
        regenerate()
    }

    private func invalidateCompositor() { cachedCompositor = nil }

    private func currentCompositor() -> FrameCompositor {
        if let c = cachedCompositor { return c }
        let c = FrameCompositor(style: style, format: format, screenSize: screenSize)
        cachedCompositor = c
        return c
    }

    public func previewImage(at t: Seconds) -> CGImage? {
        guard let result = result, let source = frameSource?.image(at: t) else { return nil }
        let crop = Director(settings: settings).cropRect(result, at: t, format: format, screen: screenSize)
        let comp = currentCompositor()
        let composed = comp.composite(source: source, crop: crop, time: t, cursor: result.cursor)
        return comp.context.createCGImage(composed, from: CGRect(origin: .zero, size: format.exportSize))
    }

    public func currentEdits() -> ProjectEdits {
        ProjectEdits(overrides: overrides, style: style, formatName: format.name, settings: settings)
    }

    public func save() throws {
        guard let url = bundleURL else { throw EditorError.notOpen }
        let data = try JSONEncoder().encode(currentEdits())
        try data.write(to: url.appendingPathComponent("project.json"), options: .atomic)
    }

    private func loadEdits(from bundle: URL) -> ProjectEdits? {
        let p = bundle.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: p) else { return nil }
        return try? JSONDecoder().decode(ProjectEdits.self, from: data)
    }

    public func export(formats: [OutputFormat], outDir: URL) throws -> [URL] {
        guard let url = bundleURL else { throw EditorError.notOpen }
        return try ExportJob.run(bundleURL: url, formats: formats, style: style,
                                 settings: settings, outDir: outDir, overrides: overrides)
    }

    public func record(target: ResolvedTarget, seconds: Double, outBundle: URL,
                       appVersion: String, createdISO: String) async throws {
        _ = try await Recorder.record(target: target, seconds: seconds, outBundle: outBundle,
                                      appVersion: appVersion, createdISO: createdISO)
        try open(outBundle)
    }

    private var recordingController: RecordingController?

    /// Begins open-ended capture. Call `stopRecording()` to finish and open the bundle.
    public func startRecording(target: ResolvedTarget, outBundle: URL,
                               appVersion: String, createdISO: String) async throws {
        let c = RecordingController(target: target, outBundle: outBundle,
                                    appVersion: appVersion, createdISO: createdISO)
        try await c.start()
        recordingController = c
    }

    /// Stops capture started by `startRecording`, writes the bundle, and opens it.
    /// No-op if not recording.
    public func stopRecording() async throws {
        guard let c = recordingController else { return }
        recordingController = nil
        let result = try await c.stop()
        try open(result.bundleURL)
    }
}
