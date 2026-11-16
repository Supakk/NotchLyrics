import SwiftUI

struct NotchContainerView: View {
    let appState: AppState
    @State private var collapseTask: Task<Void, Never>?
    @State private var artworkPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { appState.notchState == .expanded }
    private var trackingSize: CGSize {
        let size = expanded ? appState.expandedSize : AppState.hoverSize(appState.compactSize)
        let radius = AppState.cornerRadii(hasActivity: true, expanded: expanded, hasPhysicalNotch: appState.hasPhysicalNotch, notchHeight: appState.notchHeight).top
        return CGSize(width: size.width + 4 * radius, height: size.height)
    }
    var body: some View {
        NotchSurface(appState: appState, expansion: expanded ? 1 : 0, artworkPressed: $artworkPressed)
        // Keep the camera edge fixed; scale artwork, mask and progress together.
        // Native hover handler 0x1001ef16c: distinct enter/leave bounce.
        // Scope the spring to scale, so it cannot replace the geometry spring
        // when clicking artwork also changes the hover presentation.
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: appState.compactHoverActive ? 0.45 : 0.05)) { content in
            content.scaleEffect(x: appState.compactHoverActive && !reduceMotion ? AppState.compactHoverScale.width : 1, y: appState.compactHoverActive && !reduceMotion ? AppState.compactHoverScale.height : 1, anchor: .top)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.05)) { content in
            let pressed = artworkPressed && appState.compactHoverActive && !reduceMotion
            content.scaleEffect(x: pressed ? 0.94 : 1, y: pressed ? 0.90 : 1, anchor: .top)
        }
        // A fixed hover envelope avoids rebuilding its boundary during elevation.
        // The panel still passes clicks outside the actual contour to other apps.
        .frame(width: trackingSize.width, height: trackingSize.height, alignment: .top)
        .contentShape(Rectangle())
        .onChange(of: appState.isHovering) { _, hovering in
            collapseTask?.cancel()
            if !hovering && expanded {
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, !appState.isHovering else { return }
                    appState.collapse()
                }
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 25).onEnded { value in
            if abs(value.translation.width) > abs(value.translation.height) {
                if value.translation.width < 0 { appState.mediaEngine.nextTrack() }
                else { appState.mediaEngine.previousTrack() }
            } else if value.translation.height < -25 { appState.collapse() }
        })
        .onDisappear { collapseTask?.cancel() }
        .onChange(of: appState.notchState) { _, _ in notifyInputRegion() }
        .onChange(of: appState.isTucked) { _, _ in notifyInputRegion() }
        .onChange(of: appState.currentTrack.hasTrack) { _, _ in notifyInputRegion() }
        .frame(width: NotchWindowController.canvas.width, height: NotchWindowController.canvas.height, alignment: .top)
        .animation(reduceMotion ? nil : .interpolatingSpring(mass: 1, stiffness: 250, damping: 25)) { content in
            content.mask {
                Rectangle()
                    .frame(width: appState.isTucked ? max(0, appState.cameraWidth - 12) : NotchWindowController.canvas.width,
                           height: appState.isTucked ? 0 : NotchWindowController.canvas.height)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func notifyInputRegion() { NotificationCenter.default.post(name: .notchStateDidChange, object: nil) }
}

/// One animated scalar owns the frame, corners and artwork route. Derived
/// positions are rendered directly rather than starting independent animations.
private struct NotchSurface: View, Animatable {
    let appState: AppState
    var expansion: CGFloat
    @Binding var artworkPressed: Bool
    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    var body: some View {
        let visible = !appState.isTucked && appState.currentTrack.hasTrack
        let expanded = appState.notchState == .expanded
        let compactArt: CGFloat = appState.hasPhysicalNotch ? 20 : 15.5
        let compactLeading: CGFloat = appState.hasPhysicalNotch ? 7 : 6.5
        let compactRadii = AppState.cornerRadii(hasActivity: visible, expanded: false, hasPhysicalNotch: appState.hasPhysicalNotch, notchHeight: appState.notchHeight)
        let expandedRadii = AppState.cornerRadii(hasActivity: visible, expanded: true, hasPhysicalNotch: appState.hasPhysicalNotch, notchHeight: appState.notchHeight)
        let layout = NotchTransitionLayout(compact: appState.compactSize, expanded: appState.expandedSize, compactArtwork: compactArt, compactLeading: compactLeading, progress: expansion)
        let shape = NotchShape(topRadius: layout.interpolate(compactRadii.top, expandedRadii.top), bottomRadius: layout.interpolate(compactRadii.bottom, expandedRadii.bottom))
        let cornerProgress: CGFloat = expanded ? (appState.expandedCorners ? 1 : 0) : layout.progress
        let cornerMask = NotchCornerMask(compact: compactRadii, expanded: expandedRadii, progress: cornerProgress)
            .animation(expanded ? .spring(duration: 0.45, bounce: 0.4) : nil, value: appState.expandedCorners)
        let artRadius: CGFloat = (appState.hasPhysicalNotch ? 5 : 4) + (appState.compactHoverActive ? 0.5 : 0)
        ZStack(alignment: .topLeading) {
            CompactView(appState: appState)
                .frame(width: layout.size.width, height: appState.notchHeight)
                .opacity(visible ? 1 - layout.progress : 0)
                .allowsHitTesting(!expanded && visible)
                .accessibilityHidden(expanded || !visible)
            ExpandedView(appState: appState)
                .frame(width: appState.expandedSize.width, height: appState.expandedSize.height)
                .offset(x: (layout.size.width - appState.expandedSize.width) / 2)
                .opacity(appState.contentVisible ? 1 : 0)
                .blur(radius: appState.contentVisible ? 0 : 4)
                .animation(.easeOut(duration: 0.18), value: appState.contentVisible)
                .allowsHitTesting(expanded && appState.contentVisible)
                .accessibilityHidden(!expanded)
            Button { appState.toggleExpanded() } label: {
                AlbumArtView(image: appState.presentationTrack.artwork, size: layout.artwork.width, cornerRadius: layout.interpolate(artRadius, 6.6))
            }
            .buttonStyle(ArtworkPressStyle(pressed: $artworkPressed))
            .offset(x: layout.artwork.minX, y: layout.artwork.minY)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityLabel(expanded ? "Close music player" : "Open music player")
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .mask { cornerMask }
        .background { cornerMask }
        .contentShape(shape)
        .transaction { $0.animation = nil }
    }
}

private struct ArtworkPressStyle: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, down in pressed = down }
            .onDisappear { pressed = false }
    }
}

private struct NotchCornerMask: View, Animatable {
    let compact: (top: CGFloat, bottom: CGFloat)
    let expanded: (top: CGFloat, bottom: CGFloat)
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        NotchShape(topRadius: compact.top + (expanded.top - compact.top) * progress,
                   bottomRadius: compact.bottom + (expanded.bottom - compact.bottom) * progress)
            .fill(.black)
            .transaction { $0.animation = nil }
    }
}

struct NotchTransitionLayout {
    let progress: CGFloat
    let size: CGSize
    let artwork: CGRect

    init(compact: CGSize, expanded: CGSize, compactArtwork: CGFloat, compactLeading: CGFloat, progress: CGFloat) {
        let t = min(1, max(0, progress))
        self.progress = t
        func mix(_ start: CGFloat, _ end: CGFloat) -> CGFloat { start + (end - start) * t }
        size = CGSize(width: mix(compact.width, expanded.width), height: mix(compact.height, expanded.height))
        let artSize = mix(compactArtwork, 44)
        artwork = CGRect(x: mix(compactLeading, 20), y: mix((compact.height - compactArtwork) / 2, compact.height + 6), width: artSize, height: artSize)
    }

    func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat { start + (end - start) * progress }
}

extension Notification.Name {
    static let notchStateDidChange = Notification.Name("notchStateDidChange")
}
