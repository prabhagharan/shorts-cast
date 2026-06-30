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
    var body: some View {
        VStack(spacing: 0) {
            Text("ShortsCast — open a recording to begin")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundColor(.secondary)
        }
    }
}
