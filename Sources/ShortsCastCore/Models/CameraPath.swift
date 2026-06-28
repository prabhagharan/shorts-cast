import Foundation
import CoreGraphics

/// The camera at an instant: where it looks (`center`, screen px) and how tight (`scale`, 1=resting).
public struct CameraState: Equatable {
    public var center: CGPoint
    public var scale: CGFloat
    public init(center: CGPoint, scale: CGFloat) { self.center = center; self.scale = scale }
}

public struct CameraKeyframe: Equatable {
    public var t: Seconds
    public var center: CGPoint
    public var scale: CGFloat
    public init(t: Seconds, center: CGPoint, scale: CGFloat) {
        self.t = t; self.center = center; self.scale = scale
    }
    public var state: CameraState { CameraState(center: center, scale: scale) }
}

/// An editable, eased path of the virtual camera over time.
public struct CameraPath: Equatable {
    public var keyframes: [CameraKeyframe]
    public init(keyframes: [CameraKeyframe]) { self.keyframes = keyframes }

    public func sample(at t: Seconds) -> CameraState {
        guard let first = keyframes.first else {
            return CameraState(center: .zero, scale: 1)
        }
        if t <= first.t { return first.state }
        guard let last = keyframes.last, t < last.t else {
            return keyframes.last!.state
        }
        var lo = first
        for kf in keyframes {
            if kf.t <= t { lo = kf; continue }
            let hi = kf
            let span = hi.t - lo.t
            let u = span > 0 ? (t - lo.t) / span : 0
            let e = smootherstep(u)
            return CameraState(
                center: CGPoint(x: lerp(Double(lo.center.x), Double(hi.center.x), e),
                                y: lerp(Double(lo.center.y), Double(hi.center.y), e)),
                scale: CGFloat(lerp(Double(lo.scale), Double(hi.scale), e)))
        }
        return last.state
    }
}
