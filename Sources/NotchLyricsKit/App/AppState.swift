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
    var isHovering: Bool = false
    var isTucked = false
    var cameraWidth: CGFloat = 180
    var notchHeight: CGFloat = 34
    var hasPhysicalNotch = true
    var showHUD: Bool = false

    // MARK: - Services
    let mediaEngine = MediaEngine()

    let lockLyrics = LockLyrics()
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

    static func shouldTuck(hasTrack: Bool) -> Bool { !hasTrack }

    func updatePlaybackVisibility(hasTrack: Bool) {
        if !Self.shouldTuck(hasTrack: hasTrack) {
            withAnimation(NotchMotion.tuck) {
                isTucked = false
            }
        } else {
            tuck()
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
