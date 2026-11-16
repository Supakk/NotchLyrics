import SwiftUI

/// Displays album artwork, track information, controls, and playback progress.
struct ExpandedView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Album artwork and track information
            HStack(spacing: 12) {
                Color.clear.frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.presentationTrack.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(appState.presentationTrack.artist)
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
