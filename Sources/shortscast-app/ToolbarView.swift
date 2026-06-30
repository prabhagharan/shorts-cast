// Sources/shortscast-app/ToolbarView.swift
import SwiftUI
import AppKit
import ShortsCastEditor

struct ToolbarView: View {
    @ObservedObject var model: EditorModel
    @Binding var currentTime: Double
    @Binding var errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            Button("Open") { openBundle() }
            Spacer()
        }
        .padding(8)
    }

    private func openBundle() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a .shortscast bundle"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.open(url); currentTime = 0 }
        catch { errorMessage = "Open failed: \(error)" }
    }
}
