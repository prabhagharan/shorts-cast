// Sources/ShortsCastCore/AutoDirector/AutoDirectorSettings.swift
import Foundation
import CoreGraphics

/// Tunables that drive auto-zoom generation. User-facing global zoom controls live here.
public struct AutoDirectorSettings: Codable, Equatable {
    public var defaultZoom: CGFloat = 2.5
    public var maxZoom: CGFloat = 4.0
    public var restingZoom: CGFloat = 1.0
    public var clusterTimeGap: Seconds = 1.5
    public var clusterRadius: CGFloat = 300
    public var inactivityTimeout: Seconds = 1.5
    public var zoomInDuration: Seconds = 0.4
    public var zoomOutDuration: Seconds = 0.6
    public var clickWeight: Double = 1.0
    public var keyWeight: Double = 0.6
    public var scrollWeight: Double = 0.5
    public var dwellTime: Seconds = 1.0
    public var dwellRadius: CGFloat = 60
    public var dwellZoom: CGFloat = 1.6
    public var denseEventCount: Int = 5
    public var denseZoomBonus: CGFloat = 0.5

    /// Where the zoomed-out / idle camera sits, normalized 0…1 of the screen (default centered).
    public var restingAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    /// When idle, zoom out in place (keep the last focus position) instead of returning to `restingAnchor`.
    public var zoomOutInPlace: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case defaultZoom, maxZoom, restingZoom, clusterTimeGap, clusterRadius, inactivityTimeout
        case zoomInDuration, zoomOutDuration, clickWeight, keyWeight, scrollWeight
        case dwellTime, dwellRadius, dwellZoom, denseEventCount, denseZoomBonus
        case restingAnchor, zoomOutInPlace
    }

    // Tolerant decoding: every field is optional, so older project.json written before a
    // field existed still loads — missing keys fall back to the property's default.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ d: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? d
        }
        defaultZoom = get(.defaultZoom, defaultZoom);             maxZoom = get(.maxZoom, maxZoom)
        restingZoom = get(.restingZoom, restingZoom);             clusterTimeGap = get(.clusterTimeGap, clusterTimeGap)
        clusterRadius = get(.clusterRadius, clusterRadius);       inactivityTimeout = get(.inactivityTimeout, inactivityTimeout)
        zoomInDuration = get(.zoomInDuration, zoomInDuration);    zoomOutDuration = get(.zoomOutDuration, zoomOutDuration)
        clickWeight = get(.clickWeight, clickWeight);             keyWeight = get(.keyWeight, keyWeight)
        scrollWeight = get(.scrollWeight, scrollWeight);          dwellTime = get(.dwellTime, dwellTime)
        dwellRadius = get(.dwellRadius, dwellRadius);             dwellZoom = get(.dwellZoom, dwellZoom)
        denseEventCount = get(.denseEventCount, denseEventCount); denseZoomBonus = get(.denseZoomBonus, denseZoomBonus)
        restingAnchor = get(.restingAnchor, restingAnchor);       zoomOutInPlace = get(.zoomOutInPlace, zoomOutInPlace)
    }
}
