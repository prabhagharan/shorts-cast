// Sources/ShortsCastCapture/TargetResolver.swift
import Foundation
import CoreGraphics

/// A resolved capture target for AVCaptureScreenInput.
public struct ResolvedTarget {
    public let kind: String                 // "display" | "region" | "window"
    public let displayID: CGDirectDisplayID
    public let captureRectPoints: CGRect     // captured area in global points (events map into this)
    public let scale: CGFloat                // pixels per point
    public let cropRect: CGRect?             // AVCaptureScreenInput.cropRect (display-local points); nil = full display
}

public enum TargetResolver {
    public enum ResolveError: Error { case noDisplay, noWindow, badRegion }

    private static func scale(for displayID: CGDirectDisplayID, pointWidth: CGFloat) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID), pointWidth > 0 else { return 1 }
        return CGFloat(mode.pixelWidth) / pointWidth
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    /// Convert a global (top-left origin) rect into AVCaptureScreenInput.cropRect, which is in the
    /// display's local coordinate space with a bottom-left origin (Quartz). Verified by Task 4.
    private static func cropRectForDisplay(_ globalRect: CGRect, displayBounds: CGRect) -> CGRect {
        let localX = globalRect.minX - displayBounds.minX
        let topLeftY = globalRect.minY - displayBounds.minY
        let bottomLeftY = displayBounds.height - (topLeftY + globalRect.height)
        return CGRect(x: localX, y: bottomLeftY, width: globalRect.width, height: globalRect.height)
    }

    public static func resolve(displayIndex: Int?, windowQuery: String?, region: CGRect?) throws -> ResolvedTarget {
        // WINDOW
        if let query = windowQuery {
            let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
            guard let bounds = WindowFinder.selectBounds(in: list, matching: query) else { throw ResolveError.noWindow }
            let did = activeDisplays().first(where: { CGDisplayBounds($0).intersects(bounds) }) ?? CGMainDisplayID()
            let dRect = CGDisplayBounds(did)
            let clamped = bounds.intersection(dRect)
            guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { throw ResolveError.noWindow }
            let s = scale(for: did, pointWidth: dRect.width)
            return ResolvedTarget(kind: "window", displayID: did, captureRectPoints: clamped, scale: s,
                                  cropRect: cropRectForDisplay(clamped, displayBounds: dRect))
        }

        // DISPLAY selection (index into active displays; default main)
        let displays = activeDisplays()
        let did: CGDirectDisplayID
        if let idx = displayIndex {
            guard idx >= 0, idx < displays.count else { throw ResolveError.noDisplay }
            did = displays[idx]
        } else {
            did = CGMainDisplayID()
        }
        let dRect = CGDisplayBounds(did)
        let s = scale(for: did, pointWidth: dRect.width)

        // REGION
        if let region = region {
            guard dRect.contains(region) else { throw ResolveError.badRegion }
            return ResolvedTarget(kind: "region", displayID: did, captureRectPoints: region, scale: s,
                                  cropRect: cropRectForDisplay(region, displayBounds: dRect))
        }

        // FULL DISPLAY
        return ResolvedTarget(kind: "display", displayID: did, captureRectPoints: dRect, scale: s, cropRect: nil)
    }
}
