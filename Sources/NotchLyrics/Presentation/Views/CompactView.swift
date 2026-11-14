import SwiftUI

struct CompactView: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 35)
            Spacer(minLength: 0)
            CompactWaveform(isPlaying: appState.isPlaying, colors: appState.presentationColors, toggle: appState.mediaEngine.togglePlayPause)
                .frame(width: 20).padding(.trailing, appState.hasPhysicalNotch ? 7.5 : 7)
                .frame(width: 35, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            GeometryReader { geometry in
                Capsule().fill(LinearGradient(colors: appState.presentationColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geometry.size.width * appState.mediaEngine.progress), height: 2)
                    .animation(.linear(duration: 0.5), value: appState.mediaEngine.progress)
            }.frame(height: 2).padding(.horizontal, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(appState.presentationTrack.title), \(appState.presentationTrack.artist)")
    }
}

/// The native app has an independent waveform clock. This simulation uses the
/// four periods measured in its website demo; it does not sample system audio.
private struct CompactWaveform: View {
    let isPlaying: Bool
    let colors: [Color]
    let toggle: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let periods: [Double] = [0.95, 1.46, 0.82, 1.24]

    var body: some View {
        Button(action: toggle) {
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || reduceMotion)) { context in
                    Canvas { context2D, size in
                        let time = context.date.timeIntervalSinceReferenceDate
                        for index in periods.indices {
                            let phase = time / periods[index] * 2 * .pi
                            let height: CGFloat = isPlaying ? (reduceMotion ? 8 : 3 + 9 * (sin(phase) + 1) / 2) : 2
                            let rect = CGRect(x: (size.width - 12.5) / 2 + CGFloat(index) * 3.5, y: (size.height - height) / 2, width: 2, height: height)
                            context2D.fill(Path(roundedRect: rect, cornerRadius: 1), with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                        }
                    }
                }
                .blur(radius: hovering ? 3.5 : 0)
                .opacity(hovering ? 0.35 : 1)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(hovering ? 1 : 0)
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}
