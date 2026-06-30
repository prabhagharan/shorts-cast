// Sources/shortscast-app/PreviewView.swift
import SwiftUI
import ShortsCastEditor

struct PreviewView: View {
    @ObservedObject var model: EditorModel
    @Binding var currentTime: Double
    @State private var timer: Timer?
    @State private var playing = false
    @State private var startWall: Double = 0
    @State private var startTime: Double = 0

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
        // Anchor playback to the wall clock so a slow render skips frames rather
        // than playing in slow motion (the per-tick fixed step did the latter).
        startWall = Date.timeIntervalSinceReferenceDate
        startTime = currentTime >= model.duration ? 0 : currentTime
        currentTime = startTime
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            let r = PlaybackClock.tick(startWall: startWall, startTime: startTime,
                                       nowWall: Date.timeIntervalSinceReferenceDate,
                                       duration: model.duration)
            currentTime = r.time
            if !r.playing { playing = false; timer?.invalidate() }
        }
    }
}
