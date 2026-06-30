// Sources/shortscast-app/TimelineView.swift
import SwiftUI
import ShortsCastEditor

struct TimelineView: View {
    @ObservedObject var model: EditorModel
    @Binding var currentTime: Double
    private let band: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let rects = TimelineLayout.xPositions(segments: model.segments,
                                                  duration: model.duration, width: w, height: band)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.gray.opacity(0.15))
                ForEach(Array(rects.enumerated()), id: \.offset) { idx, r in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(model.selectedSegment == idx ? Color.accentColor : Color.accentColor.opacity(0.45))
                        .frame(width: max(2, r.width), height: r.height)
                        .offset(x: r.minX, y: 0)
                        .onTapGesture { model.selectedSegment = idx }
                }
                if model.duration > 0 {
                    Rectangle().fill(Color.red).frame(width: 2, height: band)
                        .offset(x: CGFloat(currentTime / model.duration) * w, y: 0)
                }
            }
        }
        .frame(height: band)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
