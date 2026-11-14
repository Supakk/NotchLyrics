import AppKit
import Combine
import Foundation
import SwiftUI

/// ศูนย์กลางจัดการข้อมูลเพลง — observe ได้จาก SwiftUI
@Observable
final class MediaEngine {
    // MARK: - Published state
    var currentTrack: TrackInfo = .empty
    var isPlaying: Bool = false
    var elapsedTime: TimeInterval = 0
    var artworkColors: [Color] = [.purple, .pink]

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
        if !playerBridge.send(.togglePlayPause) { bridge.sendCommand(.togglePlayPause) }
        // หน่วงนิดนึงแล้ว refresh เพราะ state อาจยังไม่เปลี่ยนทันที
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    func nextTrack() {
        if !playerBridge.send(.nextTrack) { bridge.sendCommand(.nextTrack) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    func previousTrack() {
        if !playerBridge.send(.previousTrack) { bridge.sendCommand(.previousTrack) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    // MARK: - Refresh

    func refreshNowPlaying() {
        playerBridge.refresh { [weak self] track in
            guard let self else { return }
            let track = track ?? .empty
            let trackChanged = !track.isSameTrack(as: self.currentTrack)

            if trackChanged || self.currentTrack.artwork !== track.artwork {
                self.artworkColors = ColorExtractor.gradient(from: track.artwork)
            }
            self.currentTrack = track
            self.isPlaying = track.isPlaying
            self.elapsedTime = track.elapsedTime

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
    // อัปเดต elapsedTime ทุก 0.5 วินาทีเพื่อให้ progress bar เลื่อน

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
