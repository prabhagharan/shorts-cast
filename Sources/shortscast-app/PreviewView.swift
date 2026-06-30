// Sources/shortscast-app/PreviewView.swift
import SwiftUI
import ShortsCastEditor

struct PreviewView: View {
    @ObservedObject var model: EditorModel
    @Binding var currentTime: Double
    @State private var timer: Timer?
    @State private var playing = false

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let cg = model.previewImage(at: currentTime) {
                    Image(decorative: cg, scale: 1.0)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle().fill(Color.black.opacity(0.85))
                        .overlay(Text("No preview").foregroundColor(.white.opacity(0.6)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button(action: togglePlay) {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                }
                Slider(value: $currentTime, in: 0...max(model.duration, 0.001))
                Text(TimeLabel.format(currentTime)).monospacedDigit().frame(width: 48)
            }
        }
        .padding(8)
        .onDisappear { timer?.invalidate() }
    }

    private func togglePlay() {
        playing.toggle()
        timer?.invalidate()
        guard playing else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            let next = currentTime + 1.0 / 30.0
            if next >= model.duration { currentTime = model.duration; playing = false; timer?.invalidate() }
            else { currentTime = next }
        }
    }
}
