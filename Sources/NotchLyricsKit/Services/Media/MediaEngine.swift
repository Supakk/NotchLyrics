import AppKit
import Combine
import Foundation
import SwiftUI

/// Provides observable playback information to SwiftUI.
@Observable
final class MediaEngine {
    // MARK: - Published state
    var currentTrack: TrackInfo = .empty
    var isPlaying: Bool = false
    var hasLoadedPlaybackState = false
    var elapsedTime: TimeInterval = 0
    var artworkColors: [Color] = ArtworkPalette.fallback

    // MARK: - Callbacks
    var onTrackChanged: ((TrackInfo) -> Void)?

    // MARK: - Private
    let playerBridge = PlayerBridge()
    private var pollTimer: Timer?
    private let bridge = MediaRemoteBridge.shared
    private var elapsedTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        setupNotifications()
        bridge.registerForNotifications()
        refreshNowPlaying()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshNowPlaying() }
    }

    deinit {
        pollTimer?.invalidate()
        elapsedTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Controls

    func togglePlayPause() {
        // Update the UI immediately; the next refresh confirms the real player state.
        isPlaying.toggle()
        if isPlaying { startElapsedTimer() } else { stopElapsedTimer() }
        if !playerBridge.send(.togglePlayPause) { bridge.sendCommand(.togglePlayPause) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    func nextTrack() {
        if !playerBridge.send(.nextTrack) { bridge.sendCommand(.nextTrack) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    /// Bundle identifier of the app playing the current track.
    private var playerBundleID: String? { currentTrack.bundleID ?? playerBridge.bundleID }

    /// Display name of the playing app, for accessibility labels.
    var playerAppName: String? {
        guard let id = playerBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Bring the app that is playing the current track to the front.
    func openPlayerApp() {
        guard let id = playerBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func previousTrack() {
        elapsedTime = 0
        if !playerBridge.send(.previousTrack) { bridge.sendCommand(.previousTrack) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    // MARK: - Refresh

    func refreshNowPlaying() {
        let generation = playerBridge.controlGeneration
        playerBridge.refresh { [weak self] track in
            guard let self else { return }
            // Ignore a poll that started before the latest button press; it holds stale state.
            guard generation == self.playerBridge.controlGeneration else { return }
            var track = track ?? .empty
            let trackChanged = !track.isSameTrack(as: self.currentTrack)
            // A poll that briefly lacks the artwork must not swap the cover for the placeholder.
            if !trackChanged, track.artwork == nil { track.artwork = self.currentTrack.artwork }

            if trackChanged || self.currentTrack.artwork !== track.artwork {
                self.artworkColors = ColorExtractor.gradient(from: track.artwork)
            }
            self.currentTrack = track
            self.isPlaying = track.isPlaying
            self.elapsedTime = track.elapsedTime
            self.hasLoadedPlaybackState = true

            if track.isPlaying {
                self.startElapsedTimer()
            } else {
                self.stopElapsedTimer()
            }

            if trackChanged {
                self.onTrackChanged?(track)
            }
        }
    }

    // MARK: - Elapsed time timer
    // Update elapsed time every half second to advance the progress bar.

    private func startElapsedTimer() {
        guard elapsedTimer == nil else { return }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            self.elapsedTime = min(self.elapsedTime + 0.5, self.currentTrack.duration)
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let dnc = NotificationCenter.default

        // Now Playing info changed
        if let name = bridge.nowPlayingInfoDidChangeNotification {
            let obs = dnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshNowPlaying()
            }
            observers.append(obs)
        }

        // Now Playing app changed
        if let name = bridge.nowPlayingApplicationDidChangeNotification {
            let obs = dnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshNowPlaying()
            }
            observers.append(obs)
        }

        // Wake from sleep → refresh
        let wakeObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.refreshNowPlaying()
            }
        }
        observers.append(wakeObs)
    }

    // MARK: - Helpers

    /// Format seconds → "1:24"
    static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    /// Progress 0.0 - 1.0
    var progress: Double {
        guard currentTrack.duration > 0 else { return 0 }
        return min(elapsedTime / currentTrack.duration, 1.0)
    }
}
