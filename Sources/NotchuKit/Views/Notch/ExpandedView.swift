import SwiftUI

/// Displays album artwork, track information, controls, and playback progress.
struct ExpandedView: View {
    let appState: AppState

    /// Time label width (34) + spacing (9) in `ProgressBarView`.
    static let titleTrailingInset: CGFloat = 43

    var body: some View {
        VStack(spacing: 0) {
            // Album artwork and track information
            HStack(spacing: 12) {
                Color.clear.frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    // Long titles scroll to the end and back while the player is open.
                    MarqueeText(
                        text: appState.presentationTrack.title,
                        fontSize: 14,
                        weight: .semibold,
                        isActive: appState.notchState == .expanded && appState.contentVisible
                    )
                    // End the title where the progress track ends (before the remaining-time
                    // label) instead of running to the edge of the notch.
                    .padding(.trailing, Self.titleTrailingInset)

                    Text(appState.presentationTrack.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, appState.notchHeight + 6)

            Spacer().frame(height: 8)

            // Progress bar
            ProgressBarView(
                progress: appState.mediaEngine.progress,
                elapsedTime: appState.mediaEngine.elapsedTime,
                duration: appState.currentTrack.duration,
                colors: appState.presentationColors
            )
            .padding(.horizontal, 20)

            Spacer().frame(height: 8)

            // Playback controls
            PlaybackControlsView(appState: appState)

            Spacer(minLength: 7)
        }
    }
}
