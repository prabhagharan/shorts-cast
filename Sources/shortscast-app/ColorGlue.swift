// Sources/shortscast-app/ColorGlue.swift
import SwiftUI
import AppKit
import ShortsCastRender

extension Color {
    init(_ rgba: RGBA) {
        self = Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

func rgba(from color: Color) -> RGBA {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
    return RGBA(Double(ns.redComponent), Double(ns.greenComponent),
                Double(ns.blueComponent), Double(ns.alphaComponent))
}
