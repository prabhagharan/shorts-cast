// Sources/ShortsCastCore/AutoDirector/AutoDirector.swift
import Foundation
import CoreGraphics

/// Turns focus segments into an editable, eased camera path (the auto-zoom).
public struct AutoDirector {
    public var settings: AutoDirectorSettings
    public init(settings: AutoDirectorSettings) { self.settings = settings }

    public func cameraPath(segments: [FocusSegment],
                           duration: Seconds,
                           screenSize: CGSize) -> CameraPath {
        let rest = CameraState(
            center: CGPoint(x: screenSize.width * settings.restingAnchor.x,
                            y: screenSize.height * settings.restingAnchor.y),
            scale: settings.restingZoom)

        var kfs: [CameraKeyframe] = [CameraKeyframe(t: 0, center: rest.center, scale: rest.scale)]
        var current = rest

        func push(_ t: Seconds, _ s: CameraState) {
            var tt = t
            if let last = kfs.last, tt <= last.t { tt = last.t + 0.001 }
            kfs.append(CameraKeyframe(t: tt, center: s.center, scale: s.scale))
            current = s
        }

        for (i, seg) in segments.enumerated() {
            let target = CameraState(center: seg.center, scale: seg.zoom)
            push(seg.start, current)                                   // hold until move begins
            push(seg.start + settings.zoomInDuration, target)         // ease in
            push(max(seg.end, seg.start + settings.zoomInDuration), target) // hold while active

            let nextStart = i + 1 < segments.count ? segments[i + 1].start : Double.infinity
            let gap = nextStart - seg.end
            // Only return to resting when there is room to complete the zoom-out
            // before the next segment begins; otherwise stay zoomed and pan.
            if gap > settings.inactivityTimeout + settings.zoomOutDuration {
                // Zoom out in place (keep the focus position) or pull back to the resting anchor.
                let out = settings.zoomOutInPlace
                    ? CameraState(center: seg.center, scale: settings.restingZoom)
                    : rest
                push(seg.end + settings.inactivityTimeout, target)    // hold, then
                push(seg.end + settings.inactivityTimeout + settings.zoomOutDuration, out) // zoom out
            }
            // else: stay zoomed; the next segment pans/zooms from `current`.
        }

        if let last = kfs.last, last.t < duration {
            push(duration, current)
        }
        return CameraPath(keyframes: kfs)
    }
}
