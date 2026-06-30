// Sources/shortscast-app/ExportSheet.swift
import SwiftUI
import AppKit
import ShortsCastEditor
import ShortsCastCore

struct ExportSheet: View {
    // Resolution multipliers applied to each format's base export size.
    private static let scales: [(label: String, factor: CGFloat)] =
        [("Standard (1×)", 1), ("High (1.5×)", 1.5), ("Max (2×)", 2)]

    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?
    @State private var selected: Set<String> = []
    @State private var scaleIndex = 0
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export formats").font(.headline)
            ForEach(OutputFormat.all, id: \.name) { fmt in
                Toggle(fmt.name, isOn: Binding(
                    get: { selected.contains(fmt.name) },
                    set: { if $0 { selected.insert(fmt.name) } else { selected.remove(fmt.name) } }))
            }
            Picker("Resolution", selection: $scaleIndex) {
                ForEach(Self.scales.indices, id: \.self) { Text(Self.scales[$0].label).tag($0) }
            }
            HStack {
                Button("Cancel") { isPresented = false }.disabled(exporting)
                Spacer()
                if exporting { ProgressView().scaleEffect(0.6) }
                Button("Export…") { startExport() }.disabled(exporting || selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onAppear { if selected.isEmpty { selected = [model.format.name] } }
    }

    private func startExport() {
        let factor = Self.scales[scaleIndex].factor
        let formats = OutputFormat.all.filter { selected.contains($0.name) }.map { $0.scaled(by: factor) }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Choose an output folder"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        exporting = true
        Task {
            do {
                let urls = try model.export(formats: formats, outDir: dir)
                await MainActor.run {
                    exporting = false; isPresented = false
                    if let first = urls.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
                }
            } catch {
                await MainActor.run { exporting = false; errorMessage = "Export failed: \(error)" }
            }
        }
    }
}
