// Sources/ShortsCastRender/RenderStyle.swift
import Foundation
import CoreGraphics
import CoreImage

public struct RGBA: Codable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var ciColor: CIColor {
        CIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

public struct RenderStyle: Codable, Equatable {
    public enum Background: Codable, Equatable {
        case solid(RGBA)
        case gradient(top: RGBA, bottom: RGBA)
    }
    public var background: Background
    public var cornerRadius: CGFloat
    public var shadowOpacity: Double
    public var shadowBlur: CGFloat
    public var shadowOffsetY: CGFloat
    public var paddingFraction: CGFloat
    public var cursorRadius: CGFloat
    public var cursorColor: RGBA
    public var rippleDuration: Double
    public var rippleMaxRadius: CGFloat

    public init(background: Background, cornerRadius: CGFloat, shadowOpacity: Double,
                shadowBlur: CGFloat, shadowOffsetY: CGFloat, paddingFraction: CGFloat,
                cursorRadius: CGFloat, cursorColor: RGBA, rippleDuration: Double,
                rippleMaxRadius: CGFloat) {
        self.background = background; self.cornerRadius = cornerRadius
        self.shadowOpacity = shadowOpacity; self.shadowBlur = shadowBlur
        self.shadowOffsetY = shadowOffsetY; self.paddingFraction = paddingFraction
        self.cursorRadius = cursorRadius; self.cursorColor = cursorColor
        self.rippleDuration = rippleDuration; self.rippleMaxRadius = rippleMaxRadius
    }

    public static let `default` = RenderStyle(
        background: .gradient(top: RGBA(0.16, 0.18, 0.30, 1), bottom: RGBA(0.05, 0.06, 0.12, 1)),
        cornerRadius: 28, shadowOpacity: 0.5, shadowBlur: 30, shadowOffsetY: 14,
        paddingFraction: 0.06, cursorRadius: 18, cursorColor: RGBA(1, 1, 1, 1),
        rippleDuration: 0.5, rippleMaxRadius: 60)
}
