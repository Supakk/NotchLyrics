import SwiftUI

/// Shuffle, previous track, play or pause, next track, and mute controls.
struct PlaybackControlsView: View {
    let appState: AppState

    // Tap counters drive one-shot symbol bounces.
    @State private var modeTaps = 0
    @State private var previousTaps = 0
    @State private var nextTaps = 0
    @State private var playTaps = 0
    @State private var muteTaps = 0

    private var bridge: PlayerBridge { appState.mediaEngine.playerBridge }

    var body: some View {
        HStack(spacing: 0) {
            // Shuffle → play in order → repeat current track
            controlButton(
                icon: playbackModeIcon,
                size: 13,
                opacity: 1,
                trigger: modeTaps,
                accessibilityLabel: playbackModeLabel
            ) {
                modeTaps += 1
                withAnimation(Self.iconSwap) { _ = bridge.send(.advancePlaybackMode) }
            }

            Spacer()

            controlButton(icon: "backward.fill", size: 16, trigger: previousTaps, accessibilityLabel: "Previous track") {
                previousTaps += 1
                appState.mediaEngine.previousTrack()
            }

            Spacer()

            // Large central play or pause button
            Button {
                playTaps += 1
                withAnimation(Self.iconSwap) { appState.mediaEngine.togglePlayPause() }
            } label: {
                SwappingSymbol(name: appState.isPlaying ? "pause.fill" : "play.fill", size: 15, weight: .bold)
                    .offset(x: appState.isPlaying ? 0 : 1.5)
                    .animation(Self.iconSwap, value: appState.isPlaying)
            }
            // No black fill behind it: the notch is already black, and a SwiftUI fill can be
            // composited on top of the glyph, hiding the play/pause icon.
            .buttonStyle(MediaControlStyle(playbackControl: true))
            .accessibilityLabel(appState.isPlaying ? "Pause" : "Play")

            Spacer()

            controlButton(icon: "forward.fill", size: 16, trigger: nextTaps, accessibilityLabel: "Next track") {
                nextTaps += 1
                appState.mediaEngine.nextTrack()
            }

            Spacer()

            controlButton(
                icon: bridge.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                size: 13,
                trigger: muteTaps,
                accessibilityLabel: bridge.isMuted ? "Unmute" : "Mute"
            ) {
                muteTaps += 1
                withAnimation(Self.iconSwap) { _ = bridge.send(.toggleMute) }
            }
        }
        .padding(.horizontal, 24)
    }

    /// Animation used when a control's symbol changes.
    static var iconSwap: Animation { NotchMotion.iconSwap }

    /// Same symbols Apple Music and Spotify use for these states.
    private var playbackModeIcon: String {
        switch bridge.playbackMode {
        case .shuffle: "shuffle"
        case .sequential: "repeat"
        case .repeatOne: "repeat.1"
        }
    }

    private var playbackModeLabel: String {
        switch bridge.playbackMode {
        case .shuffle: "Shuffle"
        case .sequential: "Play in order"
        case .repeatOne: "Repeat current track"
        }
    }

    @ViewBuilder
    private func controlButton(
        icon: String,
        size: CGFloat,
        opacity: Double = 0.85,
        trigger: Int,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SwappingSymbol(name: icon, size: size, weight: .semibold, opacity: opacity)
        }
        .buttonStyle(MediaControlStyle(playbackControl: true))
        .accessibilityLabel(accessibilityLabel)
    }
}
