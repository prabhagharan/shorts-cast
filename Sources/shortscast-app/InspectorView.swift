// Sources/shortscast-app/InspectorView.swift
import SwiftUI
import ShortsCastEditor
import ShortsCastCore
import ShortsCastRender

struct InspectorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView {
            inspectorForm
        }
        .frame(width: 276)
    }

    private var inspectorForm: some View {
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
                Text("Default × is each segment's zoom; Max × caps how far it can go.")
                    .font(.caption).foregroundColor(.secondary)
                Text("Speed — seconds, lower = snappier").font(.caption).foregroundColor(.secondary)
                durationSlider("Zoom-in", \.zoomInDuration, 0.1...1.5)
                durationSlider("Zoom-out", \.zoomOutDuration, 0.1...1.5)
                Toggle("Zoom out in place", isOn: Binding(
                    get: { model.settings.zoomOutInPlace },
                    set: { model.settings.zoomOutInPlace = $0 }))
                Text("Resting framing").font(.caption).foregroundColor(.secondary)
                anchorSlider("X", \.x)
                anchorSlider("Y", \.y)
            }
            if let sel = model.selectedSegment, sel < model.segments.count {
                Section("Selected segment") {
                    Text("Zoom ×")
                    Slider(value: Binding(
                        get: { Double(model.segments[sel].zoom) },
                        set: { model.setZoom(segment: sel, zoom: CGFloat($0)) }), in: 1...6)
                    Text("Focus point")
                    centerSlider("X", sel, \.x, model.screenSize.width)
                    centerSlider("Y", sel, \.y, model.screenSize.height)
                    Text("Speed (seconds)")
                    segmentDurationSlider("Zoom-in", sel,
                        get: { model.segments[sel].zoomInDuration ?? model.settings.zoomInDuration },
                        set: { model.setZoomInDuration(segment: sel, duration: $0) })
                    segmentDurationSlider("Zoom-out", sel,
                        get: { model.segments[sel].zoomOutDuration ?? model.settings.zoomOutDuration },
                        set: { model.setZoomOutDuration(segment: sel, duration: $0) })
                    Button("Reset") { model.clearOverride(segment: sel) }
                }
            }
        }
        .padding(8)
        .frame(width: 260)
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
    // Global ease duration (seconds), a Double keypath on settings.
    private func durationSlider(_ label: String, _ key: WritableKeyPath<AutoDirectorSettings, Double>, _ range: ClosedRange<Double>) -> some View {
        Slider(value: Binding(get: { model.settings[keyPath: key] },
                              set: { model.settings[keyPath: key] = $0 }), in: range) { Text(label) }
    }
    // Selected segment's ease duration (seconds), via get/set closures.
    private func segmentDurationSlider(_ label: String, _ sel: Int,
                                       get: @escaping () -> Double, set: @escaping (Double) -> Void) -> some View {
        Slider(value: Binding(get: get, set: set), in: 0.1...1.5) { Text(label) }
    }
    // Normalized 0…1 resting-anchor component.
    private func anchorSlider(_ label: String, _ comp: WritableKeyPath<CGPoint, CGFloat>) -> some View {
        Slider(value: Binding(get: { Double(model.settings.restingAnchor[keyPath: comp]) },
                              set: { model.settings.restingAnchor[keyPath: comp] = CGFloat($0) }), in: 0...1) { Text(label) }
    }
    // Selected segment's focus point (screen pixels) along one axis.
    private func centerSlider(_ label: String, _ sel: Int,
                              _ comp: WritableKeyPath<CGPoint, CGFloat>, _ maxV: CGFloat) -> some View {
        Slider(value: Binding(
            get: { Double(model.segments[sel].center[keyPath: comp]) },
            set: {
                var c = model.segments[sel].center
                c[keyPath: comp] = CGFloat($0)
                model.setCenter(segment: sel, center: c)
            }), in: 0...Double(max(maxV, 1))) { Text(label) }
    }
}
