// Sources/shortscast-app/RecordSheet.swift
import SwiftUI
import AppKit
import ShortsCastEditor
import ShortsCastCapture

struct RecordSheet: View {
    enum Mode: Int { case display, window }

    @ObservedObject var model: EditorModel
    @Binding var isPresented: Bool
    @Binding var errorMessage: String?
    @Binding var currentTime: Double
    @State private var recording = false
    @State private var starting = false
    @State private var stopping = false
    @State private var mode: Mode = .display
    @State private var displays: [DisplayOption] = []
    @State private var windows: [WindowOption] = []
    @State private var displayIndex = 0
    @State private var windowNumber = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New recording").font(.headline)
            Picker("Capture", selection: $mode) {
                Text("Display").tag(Mode.display)
                Text("Window").tag(Mode.window)
            }.pickerStyle(.segmented)

            if recording {
                Label("Recording… click Stop when finished.", systemImage: "record.circle")
                    .foregroundColor(.red)
            } else if mode == .display {
                Picker("Display", selection: $displayIndex) {
                    ForEach(displays, id: \.index) { Text($0.label).tag($0.index) }
                }
            } else if windows.isEmpty {
                Text("No capturable windows found.").foregroundColor(.secondary)
            } else {
                Picker("Window", selection: $windowNumber) {
                    ForEach(windows, id: \.windowNumber) { Text($0.label).tag($0.windowNumber) }
                }
            }

            HStack {
                if recording {
                    if starting || stopping { ProgressView().scaleEffect(0.6) }
                    Spacer()
                    Button("Stop") { stop() }.keyboardShortcut(.defaultAction)
                        .disabled(starting || stopping)
                } else {
                    Button("Cancel") { isPresented = false }
                    Spacer()
                    Button("Record") { start() }.disabled(mode == .window && windowNumber < 0)
                }
            }
        }
        .padding(20).frame(width: 360)
        .interactiveDismissDisabled(recording)
        .onAppear(perform: loadTargets)
    }

    private func loadTargets() {
        displays = TargetResolver.displays()
        windows = TargetResolver.windows()
        if displays.indices.contains(displayIndex) == false { displayIndex = displays.first?.index ?? 0 }
        if windowNumber < 0 { windowNumber = windows.first?.windowNumber ?? -1 }
    }

    private func start() {
        // Auto-zoom is driven by click/key/scroll events captured via CGEventTap,
        // which macOS gates behind Accessibility + Input Monitoring (Screen Recording
        // covers only the video). Without them the recording captures video but no
        // input events, so nothing zooms. Request, then refuse to waste a capture if
        // anything is still missing.
        Permissions.request()
        let missing = Permissions.status().missingNames
        guard missing.isEmpty else {
            errorMessage = "Recording needs these permissions (System Settings > "
                + "Privacy & Security): " + missing.joined(separator: ", ")
                + ". Grant them, then quit and reopen ShortsCast and record again."
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "recording.shortscast"
        panel.message = "Save the recording bundle"
        guard panel.runModal() == .OK, let out = panel.url else { return }
        recording = true; starting = true
        let captureMode = mode, dIndex = displayIndex, wNumber = windowNumber
        Task {
            do {
                let target = captureMode == .window
                    ? try TargetResolver.resolve(displayIndex: nil, windowQuery: String(wNumber), region: nil)
                    : try TargetResolver.resolve(displayIndex: dIndex, windowQuery: nil, region: nil)
                try await model.startRecording(target: target, outBundle: out,
                                               appVersion: ShortsCastCapture.version,
                                               createdISO: ISO8601DateFormatter().string(from: Date()))
                await MainActor.run { starting = false }
            } catch {
                await MainActor.run { recording = false; starting = false; errorMessage = "Record failed: \(error)" }
            }
        }
    }

    private func stop() {
        stopping = true
        Task {
            do {
                try await model.stopRecording()
                await MainActor.run { recording = false; stopping = false; isPresented = false; currentTime = 0 }
            } catch {
                await MainActor.run { recording = false; stopping = false; errorMessage = "Record failed: \(error)" }
            }
        }
    }
}
