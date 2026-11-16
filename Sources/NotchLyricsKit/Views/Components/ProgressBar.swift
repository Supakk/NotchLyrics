import SwiftUI

private struct PlaybackTimeLabel: View {
    let text: String
    let alignment: Alignment

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

/// Playback time and the artwork-colored progress track in the expanded player.
struct ProgressBarView: View {
    let progress: Double
    let elapsedTime: TimeInterval
    let duration: TimeInterval
    var colors: [Color] = [.purple, .pink]

    @AppStorage("showRemainingTime") private var showRemainingTime = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasDuration: Bool { duration.isFinite && duration > 0 }
    private var hasPosition: Bool { elapsedTime.isFinite && elapsedTime >= 0 }
    private var displayProgress: Double { progress.isFinite ? max(0, min(1, progress)) : 0 }
    private var trailingTime: String {
        guard hasDuration else { return "-:--" }
        if showRemainingTime {
            guard hasPosition else { return "-:--" }
            return "-" + MediaEngine.formatTime(max(0, duration - elapsedTime))
        }
        return MediaEngine.formatTime(duration)
    }

    var body: some View {
        HStack(spacing: 9) {
            PlaybackTimeLabel(
                text: hasPosition ? MediaEngine.formatTime(elapsedTime) : "-:--",
                alignment: .leading
            )
                .frame(width: 34, height: 22, alignment: .leading)
                .zIndex(1)
                .accessibilityLabel("Elapsed time")
                .accessibilityValue(hasPosition ? MediaEngine.formatTime(elapsedTime) : "Unavailable")

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.gray.opacity(0.25))
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * displayProgress)
                        .animation(reduceMotion ? nil : .linear(duration: 0.5), value: displayProgress)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)

            Button { showRemainingTime.toggle() } label: {
                PlaybackTimeLabel(text: trailingTime, alignment: .trailing)
                    .frame(width: 34, height: 22, alignment: .trailing)
                    .zIndex(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MediaControlStyle(cornerRadius: 4))
            .accessibilityLabel(showRemainingTime ? "Remaining time" : "Total duration")
            .accessibilityValue(trailingTime)
            .help(showRemainingTime ? "Show total duration" : "Show remaining time")
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
    }
}
