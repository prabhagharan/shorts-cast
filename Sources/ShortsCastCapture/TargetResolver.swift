// Sources/ShortsCastCapture/TargetResolver.swift
import Foundation
import CoreGraphics
import ScreenCaptureKit

@available(macOS 12.3, *)
public struct ResolvedTarget {
    public let kind: String
    public let displayID: UInt32?
    public let captureRectPoints: CGRect
    public let scale: CGFloat
    public let cropPixels: CGRect?
    public let filter: SCContentFilter
    public let configuration: SCStreamConfiguration
}

@available(macOS 12.3, *)
public enum TargetResolver {
    public enum ResolveError: Error { case noDisplay, noWindow, badRegion }

    private static func shareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { cont in
            SCShareableContent.getWithCompletionHandler { content, error in
                if let content = content { cont.resume(returning: content) }
                else { cont.resume(throwing: error ?? ResolveError.noDisplay) }
            }
        }
    }

    private static func scale(for displayID: CGDirectDisplayID, pointWidth: CGFloat) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), pointWidth > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / pointWidth
    }

    private static func config(pixelWidth: Int, pixelHeight: Int) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.width = pixelWidth
        c.height = pixelHeight
        c.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.queueDepth = 6
        return c
    }

    public static func resolve(displayIndex: Int?, windowQuery: String?, region: CGRect?) async throws -> ResolvedTarget {
        let content = try await shareableContent()

        // WINDOW
        if let query = windowQuery {
            guard let win = content.windows.first(where: { w in
                (w.owningApplication?.applicationName.localizedCaseInsensitiveContains(query) ?? false)
                || String(w.windowID) == query
            }) else { throw ResolveError.noWindow }
            let rect = win.frame
            let displayID = content.displays.first(where: { $0.frame.intersects(rect) })?.displayID
                ?? CGMainDisplayID()
            let s = scale(for: displayID, pointWidth: content.displays.first(where: { $0.displayID == displayID })?.frame.width ?? rect.width)
            let filter = SCContentFilter(desktopIndependentWindow: win)
            let cfg = config(pixelWidth: Int(rect.width * s), pixelHeight: Int(rect.height * s))
            return ResolvedTarget(kind: "window", displayID: displayID, captureRectPoints: rect,
                                  scale: s, cropPixels: nil, filter: filter, configuration: cfg)
        }

        // pick display (index into content.displays, default main)
        let display: SCDisplay
        if let idx = displayIndex {
            guard idx >= 0, idx < content.displays.count else { throw ResolveError.noDisplay }
            display = content.displays[idx]
        } else {
            guard let main = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else { throw ResolveError.noDisplay }
            display = main
        }
        let dRect = display.frame
        let s = scale(for: display.displayID, pointWidth: dRect.width)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        // REGION (crop the full-display capture to the region in pixels)
        if let region = region {
            guard dRect.contains(region) else { throw ResolveError.badRegion }
            let cfg = config(pixelWidth: Int(dRect.width * s), pixelHeight: Int(dRect.height * s))
            let cropPixels = CGRect(x: (region.minX - dRect.minX) * s,
                                    y: (region.minY - dRect.minY) * s,
                                    width: region.width * s, height: region.height * s)
            return ResolvedTarget(kind: "region", displayID: display.displayID,
                                  captureRectPoints: region, scale: s, cropPixels: cropPixels,
                                  filter: filter, configuration: cfg)
        }

        // FULL DISPLAY
        let cfg = config(pixelWidth: Int(dRect.width * s), pixelHeight: Int(dRect.height * s))
        FileHandle.standardError.write(Data("diag(resolve): displays=\(content.displays.count) chosenID=\(display.displayID) frame=\(dRect) scale=\(s) config=\(cfg.width)x\(cfg.height) minFrameInterval=\(cfg.minimumFrameInterval.value)/\(cfg.minimumFrameInterval.timescale)\n".utf8))
        return ResolvedTarget(kind: "display", displayID: display.displayID,
                              captureRectPoints: dRect, scale: s, cropPixels: nil,
                              filter: filter, configuration: cfg)
    }
}
