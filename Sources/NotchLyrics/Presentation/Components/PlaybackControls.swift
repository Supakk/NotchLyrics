import SwiftUI

/// ปุ่มควบคุมเพลง: shuffle, prev, play/pause, next, repeat
struct PlaybackControlsView: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Shuffle
            controlButton(
                icon: "shuffle",
                size: 13,
                opacity: appState.mediaEngine.playerBridge.shuffled ? 1 : 0.4
            ) {
                appState.mediaEngine.playerBridge.send(.advanceShuffle)
            }

            Spacer()

            // Previous
            controlButton(icon: "backward.fill", size: 16) {
                appState.mediaEngine.previousTrack()
            }

            Spacer()

            // Play / Pause (ปุ่มใหญ่ ตรงกลาง)
            Button {
                appState.mediaEngine.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 38, height: 38)

                    Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        // ขยับ play icon ไปขวานิดเพื่อให้ดู center
                        .offset(x: appState.isPlaying ? 0 : 1.5)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Next
            controlButton(icon: "forward.fill", size: 16) {
                appState.mediaEngine.nextTrack()
            }

            Spacer()

            // Repeat
            controlButton(
                icon: appState.mediaEngine.playerBridge.repeatMode == "one" ? "repeat.1" : "repeat",
                size: 13,
                opacity: ["off", "false"].contains(appState.mediaEngine.playerBridge.repeatMode) ? 0.4 : 1
            ) {
                appState.mediaEngine.playerBridge.send(.advanceRepeat)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func controlButton(
        icon: String,
        size: CGFloat,
        opacity: Double = 0.8,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(opacity))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
