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

    public init() {}
}
