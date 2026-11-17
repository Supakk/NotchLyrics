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
    var elapsedTime: TimeInterval = 0 {
        didSet { elapsedTimeUpdatedAt = Date() }
    }
    /// When `elapsedTime` was last set, so views can interpolate between the 0.5 s ticks.
    private(set) var elapsedTimeUpdatedAt = Date()

    /// Playback position at `date`, advancing smoothly between updates while playing.
    func playbackTime(at date: Date) -> TimeInterval {
        guard isPlaying else { return elapsedTime }
        let drift = min(max(date.timeIntervalSince(elapsedTimeUpdatedAt), 0), 1)
        return min(elapsedTime + drift, max(currentTrack.duration, elapsedTime))
    }
    var artworkColors: [Color] = ArtworkPalette.fallback

    // MARK: - Callbacks
    var onTrackChanged: ((TrackInfo) -> Void)?

    // MARK: - Private
    let playerBridge = PlayerBridge()
    private var pollTimer: Timer?
    private let bridge = MediaRemoteBridge.shared
    private var elapsedTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var coverCarryUntil: Date?

    init() {
        setupNotifications()
        bridge.registerForNotifications()
        refreshNowPlaying()
        // Every 2 s while playing; every 6 s otherwise (the players also announce changes).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isPlaying || Date().timeIntervalSince(self.lastRefreshAt) >= 6 { self.refreshNowPlaying() }
        }
        pollTimer?.tolerance = 0.4
    }

    private var updatesStopped = false

    /// Stops refreshing from the player (previews use fixed data).
    func stopUpdates() {
        updatesStopped = true
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit {
        pollTimer?.invalidate()
        elapsedTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0); DistributedNotificationCenter.default().removeObserver($0) }
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

    private var lastRefreshAt = Date.distantPast

    func refreshNowPlaying() {
        guard !updatesStopped else { return }
        lastRefreshAt = Date()
        let generation = playerBridge.controlGeneration
        playerBridge.refresh { [weak self] track in
            guard let self else { return }
            // Ignore a poll that started before the latest button press; it holds stale state.
            guard generation == self.playerBridge.controlGeneration else { return }
            var track = track ?? .empty
            let trackChanged = !track.isSameTrack(as: self.currentTrack)
            // Never flash the placeholder: while the new cover loads, keep showing the previous
            // one, for a few seconds at most (a track may genuinely have no cover).
            if track.artwork == nil, track.hasTrack {
                if trackChanged, self.currentTrack.hasTrack {
                    self.coverCarryUntil = Date().addingTimeInterval(4)
                    track.artwork = self.currentTrack.artwork
                } else if let until = self.coverCarryUntil, Date() < until {
                    track.artwork = self.currentTrack.artwork
                } else if self.coverCarryUntil == nil {
                    // A poll that briefly lacks the cover must not swap it for the placeholder.
                    track.artwork = self.currentTrack.artwork
                }
            }
            if track.artwork != nil, track.artwork !== self.currentTrack.artwork { self.coverCarryUntil = nil }

            if trackChanged || self.currentTrack.artwork !== track.artwork {
                // Palette extraction clusters pixels; keep it off the main thread so the
                // track-change animation never drops a frame.
                let artwork = track.artwork
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let colors = ColorExtractor.gradient(from: artwork)
                    DispatchQueue.main.async {
                        guard let self, self.currentTrack.artwork === artwork else { return }
                        self.artworkColors = colors
                    }
                }
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
        elapsedTimer?.tolerance = 0.05
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

        // The players announce track changes themselves; react at once instead of waiting
        // for the next poll.
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            observers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                // Music names the new track in the notification: start fetching its cover now.
                if name.hasPrefix("com.apple.Music"), let info = note.userInfo,
                   let title = info["Name"] as? String, let artist = info["Artist"] as? String {
                    self?.playerBridge.prefetchCatalogArtwork(title: title, artist: artist, album: info["Album"] as? String ?? "")
                }
                self?.refreshNowPlaying()
            })
        }
        playerBridge.onArtworkReady = { [weak self] in self?.refreshNowPlaying() }

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
