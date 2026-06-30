// Sources/shortscast-app/InspectorView.swift
import SwiftUI
import ShortsCastEditor
import ShortsCastCore
import ShortsCastRender

struct InspectorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        Form {
            Section("Format") {
                Picker("Aspect", selection: Binding(
                    get: { model.format.name },
                    set: { name in if let f = OutputFormat.all.first(where: { $0.name == name }) { model.format = f } })) {
                    ForEach(OutputFormat.all, id: \.name) { Text($0.name).tag($0.name) }
                }
            }
            Section("Background") {
                Picker("Mode", selection: Binding(get: { isGradient ? 1 : 0 }, set: { setGradient($0 == 1) })) {
                    Text("Solid").tag(0); Text("Gradient").tag(1)
                }
                if isGradient {
                    ColorPicker("Top", selection: gradientTopBinding)
                    ColorPicker("Bottom", selection: gradientBottomBinding)
                } else {
                    ColorPicker("Color", selection: solidBinding)
                }
            }
            Section("Framing") {
                slider("Corner", \.cornerRadius, 0...80)
                slider("Shadow", \.shadowOpacity, 0...1)
                slider("Padding", \.paddingFraction, 0...0.3)
            }
            Section("Auto-zoom") {
                zoomSlider("Default ×", \.defaultZoom, 1...5)
                zoomSlider("Max ×", \.maxZoom, 1...6)
            }
            if let sel = model.selectedSegment, sel < model.segments.count {
                Section("Selected segment") {
                    Slider(value: Binding(
                        get: { Double(model.segments[sel].zoom) },
                        set: { model.setZoom(segment: sel, zoom: CGFloat($0)) }), in: 1...6)
                    Button("Reset") { model.clearOverride(segment: sel) }
                }
            }
        }
        .frame(width: 260)
        .padding(8)
    }

    private var isGradient: Bool { if case .gradient = model.style.background { return true }; return false }
    private func setGradient(_ on: Bool) {
        if on { model.style.background = .gradient(top: RGBA(0.16,0.18,0.30,1), bottom: RGBA(0.05,0.06,0.12,1)) }
        else { model.style.background = .solid(RGBA(0.08,0.09,0.14,1)) }
    }
    private var solidBinding: Binding<Color> {
        Binding(get: { if case .solid(let c) = model.style.background { return Color(c) }; return .black },
                set: { model.style.background = .solid(rgba(from: $0)) })
    }
    private var gradientTopBinding: Binding<Color> {
        Binding(get: { if case .gradient(let t, _) = model.style.background { return Color(t) }; return .blue },
                set: { if case .gradient(_, let b) = model.style.background { model.style.background = .gradient(top: rgba(from: $0), bottom: b) } })
    }
    private var gradientBottomBinding: Binding<Color> {
        Binding(get: { if case .gradient(_, let b) = model.style.background { return Color(b) }; return .black },
                set: { if case .gradient(let t, _) = model.style.background { model.style.background = .gradient(top: t, bottom: rgba(from: $0)) } })
    }
    private func slider(_ label: String, _ key: WritableKeyPath<RenderStyle, CGFloat>, _ range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { Double(model.style[keyPath: key]) },
                              set: { model.style[keyPath: key] = CGFloat($0) }), in: range) { Text(label) }
    }
    private func slider(_ label: String, _ key: WritableKeyPath<RenderStyle, Double>, _ range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { model.style[keyPath: key] },
                              set: { model.style[keyPath: key] = $0 }), in: range) { Text(label) }
    }
    private func zoomSlider(_ label: String, _ key: WritableKeyPath<AutoDirectorSettings, CGFloat>, _ range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { Double(model.settings[keyPath: key]) },
                              set: { model.settings[keyPath: key] = CGFloat($0) }), in: range) { Text(label) }
    }
}
