import SwiftUI

struct NotchContainerView: View {
    let appState: AppState
    @State private var collapseTask: Task<Void, Never>?
    @State private var notchPressed = false
    @State private var hasHoveredExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { appState.notchState == .expanded }
    static func shouldScheduleCollapse(expanded: Bool, hasHoveredExpanded: Bool, hovering: Bool) -> Bool {
        expanded && hasHoveredExpanded && !hovering
    }
    private var trackingSize: CGSize {
        let size = expanded ? appState.expandedSize : AppState.hoverSize(appState.compactSize)
        let radius = AppState.cornerRadii(hasActivity: true, expanded: expanded, hasPhysicalNotch: appState.hasPhysicalNotch, notchHeight: appState.notchHeight).top
        return CGSize(width: size.width + 4 * radius, height: size.height)
    }
    var body: some View {
        NotchSurface(appState: appState, expansion: expanded ? 1 : 0, notchPressed: $notchPressed)
        // Keep the camera edge fixed; scale artwork, mask and progress together. Scope the
        // animation to the scale so it cannot replace the frame's own animation.
        .animation(reduceMotion ? nil : NotchMotion.hover(active: appState.compactHoverActive)) { content in
            content.scaleEffect(x: appState.compactHoverActive && !reduceMotion ? AppState.compactHoverScale.width : 1, y: appState.compactHoverActive && !reduceMotion ? AppState.compactHoverScale.height : 1, anchor: .top)
        }
        .animation(reduceMotion ? nil : NotchMotion.press) { content in
            let pressed = notchPressed && appState.compactHoverActive && !reduceMotion
            content.scaleEffect(x: pressed ? NotchMotion.pressedScale.width : 1, y: pressed ? NotchMotion.pressedScale.height : 1, anchor: .top)
        }
        // A fixed hover envelope avoids rebuilding its boundary during elevation.
        // The panel still passes clicks outside the actual contour to other apps.
        .frame(width: trackingSize.width, height: trackingSize.height, alignment: .top)
        .contentShape(Rectangle())
        .onChange(of: appState.isHovering) { _, hovering in
            collapseTask?.cancel()
            if hovering && expanded {
                hasHoveredExpanded = true
            } else if Self.shouldScheduleCollapse(
                expanded: expanded,
                hasHoveredExpanded: hasHoveredExpanded,
                hovering: hovering
            ) {
                collapseTask = Task { @MainActor in
                    try? await Task.sleep(for: NotchMotion.collapseDelay)
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
        .onChange(of: appState.notchState) { _, state in
            hasHoveredExpanded = state == .expanded && appState.isHovering
            notifyInputRegion()
        }
        .onChange(of: appState.isTucked) { _, _ in notifyInputRegion() }
        .onChange(of: appState.currentTrack.hasTrack) { _, hasTrack in
            notifyInputRegion()
            guard appState.mediaEngine.hasLoadedPlaybackState else { return }
            appState.updatePlaybackVisibility(hasTrack: hasTrack)
        }
        .onChange(of: appState.mediaEngine.hasLoadedPlaybackState, initial: true) { _, loaded in
            guard loaded else { return }
            appState.updatePlaybackVisibility(hasTrack: appState.currentTrack.hasTrack)
        }
        .frame(width: NotchWindowController.canvas.width, height: NotchWindowController.canvas.height, alignment: .top)
        .animation(reduceMotion ? nil : NotchMotion.tuck) { content in
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

/// One animated value drives the frame, corners and artwork; everything else is derived
/// from it instead of running separate animations.
private struct NotchSurface: View, Animatable {
    let appState: AppState
    var expansion: CGFloat
    @Binding var notchPressed: Bool
    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    var body: some View {
        let visible = !appState.isTucked && appState.currentTrack.hasTrack
        let expanded = appState.notchState == .expanded
        let compactArtwork = NotchGeometry.compactArtwork(hasPhysicalNotch: appState.hasPhysicalNotch)
        let compactRadii = AppState.cornerRadii(hasActivity: visible, expanded: false, hasPhysicalNotch: appState.hasPhysicalNotch, notchHeight: appState.notchHeight)
        let expandedRadii = AppState.cornerRadii(hasActivity: visible, expanded: true, hasPhysicalNotch: appState.hasPhysicalNotch, notchHeight: appState.notchHeight)
        let layout = NotchTransitionLayout(compact: appState.compactSize, expanded: appState.expandedSize, compactArtwork: compactArtwork.size, compactLeading: compactArtwork.leading, progress: expansion)
        let shape = NotchShape(topRadius: layout.interpolate(compactRadii.top, expandedRadii.top), bottomRadius: layout.interpolate(compactRadii.bottom, expandedRadii.bottom))
        let cornerMask = NotchCornerMask(compact: compactRadii, expanded: expandedRadii, progress: layout.progress)
        let artRadius = layout.interpolate(
            NotchGeometry.compactArtworkCornerRadius(hasPhysicalNotch: appState.hasPhysicalNotch, hovering: appState.compactHoverActive),
            NotchGeometry.expandedArtworkCornerRadius
        )
        ZStack(alignment: .topLeading) {
            CompactView(appState: appState)
                .frame(width: layout.size.width, height: appState.notchHeight)
                .opacity(visible ? NotchMotion.compactContentOpacity(progress: layout.progress) : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(expanded || !visible)
            ExpandedView(appState: appState)
                .frame(width: appState.expandedSize.width, height: appState.expandedSize.height)
                .scaleEffect(NotchMotion.expandedContentScale(frameWidth: layout.size.width, expandedWidth: appState.expandedSize.width), anchor: .top)
                .offset(x: (layout.size.width - appState.expandedSize.width) / 2)
                .opacity(appState.contentVisible ? NotchMotion.expandedContentOpacity(progress: layout.progress) : 0)
                .blur(radius: appState.contentVisible ? 0 : NotchMotion.hiddenContentBlur)
                .animation(NotchMotion.contentReveal, value: appState.contentVisible)
                .allowsHitTesting(expanded && appState.contentVisible)
                .accessibilityHidden(!expanded)
            // In the open player, clicking the artwork brings the playing app to the front.
            Button { appState.mediaEngine.openPlayerApp() } label: {
                AlbumArtView(
                    image: appState.presentationTrack.artwork,
                    size: layout.artwork.width,
                    cornerRadius: artRadius
                )
            }
            .buttonStyle(MediaControlStyle(cornerRadius: artRadius))
            .offset(x: layout.artwork.minX, y: layout.artwork.minY)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(expanded && appState.contentVisible)
            .accessibilityHidden(!expanded)
            .accessibilityLabel("Open \(appState.mediaEngine.playerAppName ?? "music app")")

            Button { appState.expand() } label: {
                Color.clear
                    .frame(width: layout.size.width, height: appState.notchHeight)
                    .contentShape(shape)
            }
            .buttonStyle(MediaControlStyle(cornerRadius: 0) { notchPressed = $0 })
            .allowsHitTesting(!expanded && visible)
            .accessibilityHidden(expanded || !visible)
            .accessibilityLabel("Open music player")
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .mask { cornerMask }
        .background { cornerMask }
        .contentShape(shape)
        .transaction { $0.animation = nil }
    }
}


extension Notification.Name {
    static let notchStateDidChange = Notification.Name("notchStateDidChange")
}
