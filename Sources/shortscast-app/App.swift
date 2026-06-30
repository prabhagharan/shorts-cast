// Sources/shortscast-app/App.swift
import SwiftUI
import ShortsCastEditor

@main
struct ShortsCastApp: App {
    @StateObject private var model = EditorModel()
    var body: some Scene {
        WindowGroup("ShortsCast") {
            RootView(model: model)
                .frame(minWidth: 960, minHeight: 640)
        }
    }
}

struct RootView: View {
    @ObservedObject var model: EditorModel
    @State private var currentTime: Double = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(model: model, currentTime: $currentTime, errorMessage: $errorMessage)
            Divider()
            PreviewView(model: model, currentTime: $currentTime)
            Divider()
            TimelineView(model: model, currentTime: $currentTime)
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil },
                                             set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
