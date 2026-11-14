import AppKit
import SwiftUI

final class NotchWindowController {
    private var panel: NSPanel!
    private let appState: AppState
    private var screenObserver: NSObjectProtocol?
    private var globalMouse: Any?
    private var localMouse: Any?
    static let canvas = CGSize(width: 624, height: 320)

    init(appState: AppState) {
        self.appState = appState
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.canvas), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        let host = NotchHostingView(rootView: NotchContainerView(appState: appState))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        positionAtNotch()
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] _ in self?.updateMousePassthrough() }
        localMouse = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]) { [weak self] event in self?.updateMousePassthrough(); return event }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.positionAtNotch() }
    }

    var screen: NSScreen? { NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first }
    func positionAtNotch() {
        guard let screen else { return }
        appState.hasPhysicalNotch = screen.safeAreaInsets.top > 0
        appState.notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 24
        var cameraCenter = screen.frame.midX
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            appState.cameraWidth = max(0, right.minX - left.maxX)
            cameraCenter = (left.maxX + right.minX) / 2
        } else { appState.cameraWidth = 74 }
        panel.setFrame(NSRect(x: cameraCenter - Self.canvas.width / 2, y: screen.frame.maxY - Self.canvas.height, width: Self.canvas.width, height: Self.canvas.height), display: true)
        updateMousePassthrough()
    }

    func updateSize(animated: Bool = true) { updateMousePassthrough() }
    private func updateMousePassthrough() {
        // The transparent canvas must never block clicks in the applications below it.
        guard !appState.isTucked, let screen else { panel.ignoresMouseEvents = true; appState.isHovering = false; return }
        let size = appState.interactionSize
        let mouse = NSEvent.mouseLocation
        let scale = appState.transitionPhase == .compact && appState.compactHoverActive ? AppState.compactHoverScale : CGSize(width: 1, height: 1)
        let point = CGPoint(x: (mouse.x - panel.frame.midX + size.width / 2) / scale.width, y: (screen.frame.maxY - mouse.y) / scale.height)
        let radii = appState.cornerRadii
        let contour = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
        let unscaledSize = CGSize(width: size.width / scale.width, height: size.height / scale.height)
        panel.ignoresMouseEvents = !contour.path(in: CGRect(origin: .zero, size: unscaledSize)).contains(point)
        // The first move into a click-through panel can belong to another app.
        // Both event monitors use the same screen-space contour for entry and exit.
        let hovering = !panel.ignoresMouseEvents
        if appState.isHovering != hovering { appState.isHovering = hovering }
    }
    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    deinit {
        if let globalMouse { NSEvent.removeMonitor(globalMouse) }
        if let localMouse { NSEvent.removeMonitor(localMouse) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }
}

private final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }
}
