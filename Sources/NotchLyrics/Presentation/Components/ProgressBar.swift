import SwiftUI

/// A draggable playback progress bar for seeking.
struct ProgressBarView: View {
    let progress: Double
    let elapsedTime: TimeInterval
    let duration: TimeInterval

    var colors: [Color] = [.purple, .pink]
    private var displayProgress: Double { progress.isFinite ? max(0, min(1, progress)) : 0 }

    var body: some View {
        VStack(spacing: 4) {
            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 4)

                    // Fill
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * displayProgress, height: 4)
                        .animation(.linear(duration: 0.5), value: displayProgress)

                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)

            // Time labels
            HStack {
                Text(MediaEngine.formatTime(elapsedTime))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Text(MediaEngine.formatTime(duration))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
