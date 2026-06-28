import Foundation

public func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    min(max(v, lo), hi)
}

public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

/// Perlin smootherstep: 6x^5 - 15x^4 + 10x^3, with x clamped to [0,1].
public func smootherstep(_ x: Double) -> Double {
    let t = clampD(x, 0, 1)
    return t * t * t * (t * (t * 6 - 15) + 10)
}
