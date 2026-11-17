import SwiftUI

/// Presentation states for the notch.
enum NotchState: Equatable {
    case compact      // Small pill around the notch
    case expanded     // Album artwork and playback controls
}

/// Shared state observed by SwiftUI.
@Observable
final class AppState {
    // MARK: - UI State
    var notchState: NotchState = .compact
    var isHovering: Bool = false {
        // Leaving the notch entirely may not reach the waveform's own hover handler.
        didSet { if !isHovering && compactRightHover { compactRightHover = false } }
    }
    var isTucked = false
    var cameraWidth: CGFloat = 180
    var notchHeight: CGFloat = 34
    var hasPhysicalNotch = true
    var showHUD: Bool = false

    // MARK: - Services
    let mediaEngine = MediaEngine()

    let lockLyrics = LockLyrics()
    /// Drives the lock-screen card in and out with SwiftUI instead of flipping the window alpha.
    var lockScreenVisible = false
    init() {
        mediaEngine.onTrackChanged = { [weak self] track in self?.lockLyrics.load(track) }
    }

    // MARK: - Computed
    var currentTrack: TrackInfo { mediaEngine.currentTrack }
    var isPlaying: Bool { mediaEngine.isPlaying }

    // MARK: - State transitions

    private(set) var transitionPhase: TransitionPhase = .compact
    private(set) var contentVisible = false
    private var frozenTrack: TrackInfo?
    private var frozenColors: [Color]?
    var presentationTrack: TrackInfo { frozenTrack ?? currentTrack }
    var presentationColors: [Color] { frozenColors ?? mediaEngine.artworkColors }
    private var transitionGeneration = 0
    private var contentTask: Task<Void, Never>?

    enum TransitionPhase { case compact, expanding, expanded, collapsing }

    func expand() {
        guard notchState != .expanded else { return }
        transition(to: .expanded)
    }

    func collapse() {
        guard notchState != .compact else { return }
        transition(to: .compact)
    }

    private func transition(to target: NotchState) {
        frozenTrack = presentationTrack
        frozenColors = presentationColors
        contentTask?.cancel()
        transitionGeneration += 1
        let generation = transitionGeneration
        transitionPhase = target == .expanded ? .expanding : .collapsing
        isTucked = false
        let animation = target == .expanded ? NotchMotion.expand : NotchMotion.collapse
        // Swap state only once the animation has visually finished.
        withAnimation(animation, completionCriteria: .removed) {
            notchState = target
            if target == .compact { contentVisible = false }
        } completion: { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.transitionPhase = target == .expanded ? .expanded : .compact
                self.frozenTrack = nil
                self.frozenColors = nil
            }
            NotificationCenter.default.post(name: .notchStateDidChange, object: nil)
        }
        if target == .expanded {
            contentTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: NotchMotion.contentRevealDelay)
                guard let self, !Task.isCancelled, generation == self.transitionGeneration else { return }
                withAnimation(NotchMotion.contentReveal) { self.contentVisible = true }
            }
        }
    }

    func toggleExpanded() {
        if notchState == .compact {
            expand()
        } else {
            collapse()
        }
    }

    // MARK: - Notch sizing

    static func compactSize(cameraWidth: CGFloat, topInset: CGFloat, hasActivity: Bool, hasPhysicalNotch: Bool) -> CGSize {
        NotchGeometry.compactSize(cameraWidth: cameraWidth, topInset: topInset, hasActivity: hasActivity, hasPhysicalNotch: hasPhysicalNotch)
    }

    static func expandedSize(cameraWidth: CGFloat, topInset: CGFloat) -> CGSize {
        NotchGeometry.expandedSize(cameraWidth: cameraWidth, topInset: topInset)
    }
    var expandedSize: CGSize { Self.expandedSize(cameraWidth: cameraWidth, topInset: notchHeight) }
    static func cornerRadii(hasActivity: Bool, expanded: Bool, hasPhysicalNotch: Bool = true, notchHeight: CGFloat = 34) -> (top: CGFloat, bottom: CGFloat) {
        NotchGeometry.cornerRadii(hasActivity: hasActivity, expanded: expanded, hasPhysicalNotch: hasPhysicalNotch, notchHeight: notchHeight)
    }
    var cornerRadii: (top: CGFloat, bottom: CGFloat) {
        Self.cornerRadii(hasActivity: currentTrack.hasTrack && !isTucked, expanded: notchState == .expanded, hasPhysicalNotch: hasPhysicalNotch, notchHeight: notchHeight)
    }
    static var compactHoverScale: CGSize { NotchMotion.hoverScale }
    static func hoverSize(_ size: CGSize) -> CGSize { NotchGeometry.hoverSize(size) }
    var compactHoverActive: Bool {
        isHovering && notchState == .compact && !isTucked && currentTrack.hasTrack
    }
    var interactionSize: CGSize {
        switch transitionPhase {
        case .expanding, .collapsing: return expandedSize
        default: return compactHoverActive ? Self.hoverSize(notchSize) : notchSize
        }
    }

    func tuck() {
        collapse()
        withAnimation(NotchMotion.tuck) { isTucked = true }
    }

    /// Hide behind the camera when nothing is queued, or once playback has been paused for a while.
    static func shouldTuck(hasTrack: Bool, isPlaying: Bool = true, pausedLongEnough: Bool = false) -> Bool {
        !hasTrack || (!isPlaying && pausedLongEnough)
    }

    private var pauseTask: Task<Void, Never>?

    /// Pointer over the waveform on the right of the closed notch.
    var compactRightHover = false

    /// What the right of the closed notch shows instead of the waveform, if anything: the
    /// symbol just acted on after a click, else the available action while hovered.
    var compactRightSymbol: String? {
        if let compactPlaybackSymbol { return compactPlaybackSymbol }
        guard compactRightHover, compactHoverActive else { return nil }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    /// Symbol briefly shown in place of the closed notch's waveform after it is clicked.
    private(set) var compactPlaybackSymbol: String?
    private var compactSymbolTask: Task<Void, Never>?

    /// Play or pause from the closed notch's waveform, briefly showing what was done.
    func togglePlaybackFromCompact() {
        let willPlay = !isPlaying
        mediaEngine.togglePlayPause()
        compactSymbolTask?.cancel()
        compactPlaybackSymbol = willPlay ? "play.fill" : "pause.fill"
        compactSymbolTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, !Task.isCancelled else { return }
            self.compactPlaybackSymbol = nil
        }
    }

    /// A paused track stays reachable behind the camera: pointing at the camera
    /// housing only raises a thin rim around it (the hover elevation applied to the bare
    /// camera-sized shape); clicking it opens the player.
    var canPeekFromCamera: Bool { isTucked && currentTrack.hasTrack && !isScreenLocked && hasPhysicalNotch }
    /// Pointer is over the camera while the notch is tucked.
    var cameraRimActive: Bool { isHovering && canPeekFromCamera }
    /// Hover elevation applies to the closed notch and to the bare camera rim alike.
    var hoverElevated: Bool { compactHoverActive || cameraRimActive }

    /// While the screen is locked the live activity stays inside the camera housing.
    private(set) var isScreenLocked = false
    private var unlockTask: Task<Void, Never>?

    /// Lock: close the notch into the camera at once. Unlock: let the lock screen fade first,
    /// then ease the activity back out on the usual spring.
    func setScreenLocked(_ locked: Bool) {
        unlockTask?.cancel()
        if locked {
            isScreenLocked = true
            tuck()
        } else if isScreenLocked {
            unlockTask = Task { @MainActor [weak self] in
                // A screensaver stopping or the lock UI hiding does not always mean the session
                // unlocked; wait for the session to report unlocked (bounded, never stuck).
                for _ in 0..<8 {
                    try? await Task.sleep(for: .milliseconds(450))
                    if Task.isCancelled { return }
                    if !AppDelegate.isScreenLocked { break }
                }
                guard let self else { return }
                self.isScreenLocked = false
                self.updatePlaybackVisibility(hasTrack: self.currentTrack.hasTrack, isPlaying: self.isPlaying)
            }
        }
    }

    func updatePlaybackVisibility(hasTrack: Bool, isPlaying: Bool = true) {
        pauseTask?.cancel()
        if Self.shouldTuck(hasTrack: hasTrack) || isScreenLocked {
            tuck()
        } else if isPlaying {
            withAnimation(NotchMotion.untuck) { isTucked = false }
        } else if !isTucked {
            // Paused: keep the player a few seconds so it can be resumed, then tuck away.
            pauseTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled, !self.isPlaying, !self.isHovering,
                      self.notchState == .compact else { return }
                self.tuck()
            }
        }
    }

    var compactSize: CGSize {
        Self.compactSize(cameraWidth: cameraWidth, topInset: notchHeight, hasActivity: !isTucked && currentTrack.hasTrack, hasPhysicalNotch: hasPhysicalNotch)
    }

    var notchSize: CGSize {
        switch notchState {
        case .compact:
            return compactSize
        case .expanded:
            return expandedSize
        }
    }
}
