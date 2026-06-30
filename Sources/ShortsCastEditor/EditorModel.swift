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
    @Published public private(set) var screenSize: CGSize = .zero
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
        bundleURL = url
        eventLog = log
        rawVideoURL = raw
        screenSize = log.screenSize
        overrides = []
        settings = AutoDirectorSettings()
        style = .default
        format = .vertical9x16
        frameSource = AVAssetFrameSource(url: raw)
        cachedCompositor = nil
        isLoading = false
        regenerate()
    }

    func regenerate() {
        guard let log = eventLog else { return }
        result = Director(settings: settings).direct(log: log, overrides: overrides)
    }

    func invalidateCompositor() { cachedCompositor = nil }
}
