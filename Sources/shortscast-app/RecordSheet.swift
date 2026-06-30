// Sources/shortscast-app/RecordSheet.swift
import SwiftUI
import AppKit
import ShortsCastEditor
import ShortsCastCapture

struct RecordSheet: View {
    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?
    @Binding var currentTime: Double
    @State private var seconds: Double = 5
    @State private var recording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New recording (main display)").font(.headline)
            HStack { Text("Duration"); Slider(value: $seconds, in: 2...30); Text("\(Int(seconds))s").frame(width: 36) }
            HStack {
                Button("Cancel") { isPresented = false }.disabled(recording)
                Spacer()
                if recording { ProgressView().scaleEffect(0.6) }
                Button("Record") { start() }.disabled(recording)
            }
        }
        .padding(20).frame(width: 320)
    }

    private func start() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "recording.shortscast"
        panel.message = "Save the recording bundle"
        guard panel.runModal() == .OK, let out = panel.url else { return }
        recording = true
        Task {
            do {
                let target = try TargetResolver.resolve(displayIndex: nil, windowQuery: nil, region: nil)
                try await model.record(target: target, seconds: seconds, outBundle: out,
                                       appVersion: ShortsCastCapture.version,
                                       createdISO: ISO8601DateFormatter().string(from: Date()))
                await MainActor.run { recording = false; isPresented = false; currentTime = 0 }
            } catch {
                await MainActor.run { recording = false; errorMessage = "Record failed: \(error)" }
            }
        }
    }
}
