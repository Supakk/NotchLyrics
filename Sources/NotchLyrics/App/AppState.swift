import SwiftUI

/// สถานะ UI ของ notch
enum NotchState: Equatable {
    case compact      // pill เล็กตรง notch
    case expanded     // ขยาย: album art + controls
}

/// Global app state — ใช้ @Observable เพื่อให้ SwiftUI track ได้ทั้งหมด
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
    private(set) var expandedCorners = false
    private var frozenTrack: TrackInfo?
    private var frozenColors: [Color]?
    var presentationTrack: TrackInfo { frozenTrack ?? currentTrack }
    var presentationColors: [Color] { frozenColors ?? mediaEngine.artworkColors }
    private var transitionGeneration = 0
    private var contentTask: Task<Void, Never>?
    private var cornerTask: Task<Void, Never>?

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
        cornerTask?.cancel()
        expandedCorners = false
        transitionGeneration += 1
        let generation = transitionGeneration
        transitionPhase = target == .expanded ? .expanding : .collapsing
        isTucked = false
        // Native evidence uses separate critically damped geometry and content phases.
        // These choices remain our implementation until all original caller flags are mapped.
        let animation = Animation.spring(response: target == .expanded ? 0.4 : 0.25, dampingFraction: 1)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
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
            cornerTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(20))
                guard let self, !Task.isCancelled, generation == self.transitionGeneration else { return }
                withAnimation(.spring(duration: 0.45, bounce: 0.4)) { self.expandedCorners = true }
            }
            contentTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !Task.isCancelled, generation == self.transitionGeneration else { return }
                withAnimation(.easeOut(duration: 0.18)) { self.contentVisible = true }
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
        // Visible frame: 0x10012aed0 -> 0x10022b480 -> NotchView FrameLayout.
        CGSize(width: cameraWidth + (hasActivity ? (hasPhysicalNotch ? 74 : 62) : 0), height: topInset)
    }

    static func expandedSize(cameraWidth: CGFloat, topInset: CGFloat) -> CGSize {
        CGSize(width: min(cameraWidth + 160, 345), height: max(topInset + 142, 175))
    }
    var expandedSize: CGSize { Self.expandedSize(cameraWidth: cameraWidth, topInset: notchHeight) }
    static func cornerRadii(hasActivity: Bool, expanded: Bool, hasPhysicalNotch: Bool = true, notchHeight: CGFloat = 34) -> (top: CGFloat, bottom: CGFloat) {
        // Native NotchView -> 0x10012bf6c / 0x10012c3d0 -> NotchShape.
        if !hasPhysicalNotch {
            let radius: CGFloat = expanded ? 36 : notchHeight / 2
            return (radius, radius)
        }
        return (top: (hasActivity ? 8 : 5) + (expanded ? 12 : 0),
                bottom: (hasActivity ? 11.5 : 10) + (expanded ? 24 : 0))
    }
    var cornerRadii: (top: CGFloat, bottom: CGFloat) {
        Self.cornerRadii(hasActivity: currentTrack.hasTrack && !isTucked, expanded: notchState == .expanded, hasPhysicalNotch: hasPhysicalNotch, notchHeight: notchHeight)
    }
    // Root NotchShape composition 0x1001e4910: independent axes, top anchor.
    static let compactHoverScale = CGSize(width: 1.075, height: 1.15)
    static func hoverSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width * compactHoverScale.width, height: size.height * compactHoverScale.height)
    }
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
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 250, damping: 25)) { isTucked = true }
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
