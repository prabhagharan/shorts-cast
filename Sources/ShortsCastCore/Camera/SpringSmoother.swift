import Foundation
import CoreGraphics

public struct TimedPoint: Equatable {
    public var t: Seconds
    public var p: CGPoint
    public init(t: Seconds, p: CGPoint) { self.t = t; self.p = p }
}

/// Critically-damped spring filter for smoothing a stream of points (e.g. cursor motion).
public struct SpringSmoother {
    /// Natural angular frequency (higher = snappier tracking).
    public var omega: Double
    public init(frequency: Double = 6) { self.omega = 2 * Double.pi * frequency }

    public func smooth(_ samples: [TimedPoint]) -> [TimedPoint] {
        guard let first = samples.first else { return [] }
        var posX = Double(first.p.x), posY = Double(first.p.y)
        var velX = 0.0, velY = 0.0
        var out: [TimedPoint] = [first]

        for i in 1..<samples.count {
            let dt = max(samples[i].t - samples[i-1].t, 1e-4)
            let tx = Double(samples[i].p.x), ty = Double(samples[i].p.y)
            // Substep so that omega * subDt stays small enough for the
            // semi-implicit integrator to remain stable at any input rate.
            let steps = max(1, Int((omega * dt / 0.3).rounded(.up)))
            let subDt = dt / Double(steps)
            for _ in 0..<steps {
                // Critically damped: x'' = ω²(target - x) - 2ω x'
                let ax = omega * omega * (tx - posX) - 2 * omega * velX
                let ay = omega * omega * (ty - posY) - 2 * omega * velY
                velX += ax * subDt; velY += ay * subDt   // semi-implicit Euler
                posX += velX * subDt; posY += velY * subDt
            }
            out.append(TimedPoint(t: samples[i].t, p: CGPoint(x: posX, y: posY)))
        }
        return out
    }
}
