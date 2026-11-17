import AppKit
import OSLog
import SwiftUI
import ServiceManagement

private typealias CGSConnectionID = UInt32
private typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ connection: CGSConnectionID, _ type: Int32, _ options: CFDictionary?) -> CGSSpaceID
@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ connection: CGSConnectionID, _ space: CGSSpaceID, _ level: Int32)
@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ connection: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)
@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ connection: CGSConnectionID, _ spaces: CFArray)
@_silgen_name("CGSHideSpaces")
private func CGSHideSpaces(_ connection: CGSConnectionID, _ spaces: CFArray)
@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ connection: CGSConnectionID, _ space: CGSSpaceID)

/// Manages the menu bar item, window lifecycle, and mouse tracking.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let lockLogger = Logger(subsystem: "com.notchlyrics.app", category: "LockScreen")
    private var windowController: NotchWindowController!
    private var statusItem: NSStatusItem!
    private let appState = AppState()
    private var lockPanel: NSPanel?
    private var lockPanelTask: Task<Void, Never>?
    private var lockSpaceID: CGSSpaceID?
    private var lockScreenActivity: NSObjectProtocol?
    private var lockObservers: [NSObjectProtocol] = []
    private var stateObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the Dock icon. Info.plist also sets LSUIElement.
        NSApp.setActivationPolicy(.accessory)

        // Create the notch window.
        windowController = NotchWindowController(appState: appState)
        windowController.show()

        // Create the menu bar item.
        setupLockScreen()
        setupStatusItem()
        HotKeyManager.shared.registerDefaults(appState: appState)

        // Monitor the pointer so the player can collapse when it leaves the notch.
        // Hover lifecycle is owned by the view to avoid competing collapse timers.

        // Update the window when the notch state changes.
        stateObserver = NotificationCenter.default.addObserver(
            forName: .notchStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.windowController.updateSize()
        }

        print("[App] ✅ NotchLyrics launched")
    }

    private func setupLockScreen() {
        prepareLockPanelIfNeeded()
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenLockUIIsShown", "com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            center.addObserver(
                self,
                selector: #selector(lockScreenDidAppear(_:)),
                name: Notification.Name(name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }
        for name in ["com.apple.screenLockUIIsHidden", "com.apple.screenIsUnlocked", "com.apple.screensaver.didstop"] {
            center.addObserver(
                self,
                selector: #selector(lockScreenDidDisappear(_:)),
                name: Notification.Name(name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }

        let workspace = NSWorkspace.shared.notificationCenter
        lockObservers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.appState.setScreenLocked(true)
            self?.showLockPanel(reason: "NSWorkspace.sessionDidResignActive")
        })
        lockObservers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.appState.setScreenLocked(false)
            self?.hideLockPanel(reason: "NSWorkspace.sessionDidBecomeActive")
        })
    }

    @objc private func lockScreenDidAppear(_ notification: Notification) {
        appState.setScreenLocked(true)
        showLockPanel(reason: notification.name.rawValue)
    }

    @objc private func lockScreenDidDisappear(_ notification: Notification) {
        appState.setScreenLocked(false)
        hideLockPanel(reason: notification.name.rawValue)
    }

    private func prepareLockPanelIfNeeded() {
        guard lockPanel == nil else { return }
        let screen = NSScreen.screens.max { $0.safeAreaInsets.top < $1.safeAreaInsets.top } ?? NSScreen.main
        guard let screen else { return }
        let panel = NSPanel(
            contentRect: Self.lockPanelFrame(in: screen.frame),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.canBecomeVisibleWithoutLogin = true
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.isOpaque = false
        // The window server outlines a shadowed borderless window; that faint edge showed around
        // the transparent panel on the lock screen. The card draws its own soft shadow.
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LockLyricsView(state: appState))
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        lockPanel = panel
        // Keep the window registered with WindowServer before macOS switches to loginwindow.
        // Ordering a brand-new window after the secure session appears is too late.
        panel.orderFrontRegardless()
        attachLockPanelToLoginSpace(panel)
        Self.lockLogger.notice("Panel prepared and staged")
    }

    private func attachLockPanelToLoginSpace(_ panel: NSPanel) {
        let connection = CGSMainConnectionID()
        let space = lockSpaceID ?? CGSSpaceCreate(connection, 1, nil)
        guard space != 0 else {
            Self.lockLogger.error("Unable to create the login presentation space")
            return
        }
        if lockSpaceID == nil {
            CGSSpaceSetAbsoluteLevel(connection, space, 400)
            lockSpaceID = space
        }
        let spaces = [NSNumber(value: space)] as CFArray
        let windows = [NSNumber(value: panel.windowNumber)] as CFArray
        CGSAddWindowsToSpaces(connection, windows, spaces)
        CGSShowSpaces(connection, spaces)
        Self.lockLogger.notice("Panel attached to login presentation space \(space)")
    }

    private func setLockSpaceVisible(_ visible: Bool) {
        guard let lockSpaceID else { return }
        let spaces = [NSNumber(value: lockSpaceID)] as CFArray
        if visible { CGSShowSpaces(CGSMainConnectionID(), spaces) }
        else { CGSHideSpaces(CGSMainConnectionID(), spaces) }
    }

    private func showLockPanel(reason: String) {
        guard Self.lockLyricsEnabled else {
            Self.lockLogger.notice("Ignored \(reason, privacy: .public) because the feature is disabled")
            return
        }
        prepareLockPanelIfNeeded()
        guard let panel = lockPanel else { return }
        Self.lockLogger.notice("Showing for \(reason, privacy: .public); CGSession locked=\(Self.isScreenLocked)")
        appState.lockLyrics.load(appState.currentTrack)
        if lockScreenActivity == nil {
            lockScreenActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Keep synchronized lock-screen lyrics moving with Apple Music"
            )
        }
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        // The card animates in with SwiftUI rather than the window popping to full opacity.
        appState.lockScreenVisible = true
        setLockSpaceVisible(true)
        panel.orderFrontRegardless()

        // Re-order once the secure Lock UI has finished changing window layers.
        lockPanelTask?.cancel()
        lockPanelTask = Task { @MainActor [weak panel] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            panel?.alphaValue = 1
            panel?.orderFrontRegardless()
        }
    }

    private func hideLockPanel(reason: String = "feature disabled") {
        Self.lockLogger.notice("Hiding for \(reason, privacy: .public)")
        lockPanelTask?.cancel()
        // Let the card fade out with SwiftUI first (it stays above the lock screen while
        // that fades away too), then take the window down.
        appState.lockScreenVisible = false
        lockPanel?.ignoresMouseEvents = true
        lockPanelTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, !self.appState.lockScreenVisible else { return }
            self.lockPanel?.alphaValue = 0
            self.setLockSpaceVisible(false)
            if let activity = self.lockScreenActivity {
                ProcessInfo.processInfo.endActivity(activity)
                self.lockScreenActivity = nil
            }
        }
    }

    static var isScreenLocked: Bool {
        isLocked(session: CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    static func isLocked(session: [String: Any]?) -> Bool {
        session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private static var lockLyricsEnabled: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        return (CFPreferencesCopyAppValue("lockLyricsEnabled" as CFString, kCFPreferencesCurrentApplication) as? Bool) ?? true
    }

    static func lockPanelFrame(in screenFrame: NSRect) -> NSRect {
        // Room for the card beside the lyrics, a little below the middle of the screen.
        // Transparent parts of the panel pass clicks through to the lock screen.
        let size = NSSize(width: min(860, max(320, screenFrame.width - 40)), height: 410)
        return NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2 - screenFrame.height * 0.06,
            width: size.width,
            height: size.height
        )
    }

    /// Shows the lock-screen player over the desktop so it can be checked without locking.
    @objc private func toggleLockPreview(_ sender: NSMenuItem) {
        if appState.lockScreenVisible {
            hideLockPanel(reason: "preview closed")
            sender.state = .off
            return
        }
        prepareLockPanelIfNeeded()
        guard let panel = lockPanel else { return }
        appState.lockLyrics.load(appState.currentTrack)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        setLockSpaceVisible(true)
        panel.orderFrontRegardless()
        appState.lockScreenVisible = true
        sender.state = .on
    }

    @objc private func toggleLockLyrics(_ sender: NSMenuItem) {
        let enabled = !Self.lockLyricsEnabled
        CFPreferencesSetAppValue("lockLyricsEnabled" as CFString, enabled as CFBoolean, kCFPreferencesCurrentApplication)
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        sender.state = enabled ? .on : .off
        if enabled { prepareLockPanelIfNeeded() } else { hideLockPanel() }
    }

    // MARK: - Status Item (Menu Bar)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "music.note",
                accessibilityDescription: "NotchLyrics"
            )
            button.image?.size = NSSize(width: 16, height: 16)
        }

        let menu = NSMenu()

        menu.addItem(withTitle: "NotchLyrics v1.0", action: nil, keyEquivalent: "")
        menu.items.first?.isEnabled = false

        menu.addItem(withTitle: "Hide in Camera Notch", action: #selector(tuckNotch), keyEquivalent: "")
        let sourceMenu = NSMenu()
        for (title, value) in [("Automatic", "automatic"), ("Apple Music", "com.apple.Music"), ("Spotify", "com.spotify.client")] {
            let item = sourceMenu.addItem(withTitle: title, action: #selector(selectSource(_:)), keyEquivalent: "")
            item.representedObject = value
            item.target = self
            item.state = appState.mediaEngine.playerBridge.selectedSource == value ? .on : .off
        }
        let sourceItem = menu.addItem(withTitle: "Music Source", action: nil, keyEquivalent: "")
        sourceItem.submenu = sourceMenu
        let lyricsItem = menu.addItem(withTitle: "Lyrics on Lock Screen", action: #selector(toggleLockLyrics(_:)), keyEquivalent: "")
        lyricsItem.state = Self.lockLyricsEnabled ? .on : .off
        menu.addItem(withTitle: "Preview Lock Screen Player", action: #selector(toggleLockPreview(_:)), keyEquivalent: "")
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Show / Hide",
            action: #selector(toggleNotch),
            keyEquivalent: "n"
        )

        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )

        // Route each menu action to the app delegate.
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Open at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        appState.mediaEngine.playerBridge.selectedSource = value
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
        appState.mediaEngine.refreshNowPlaying()
    }

    @objc private func tuckNotch() { appState.tuck() }

    @objc private func toggleNotch() {
        appState.toggleExpanded()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Cleanup

    func applicationWillTerminate(_ notification: Notification) {
        lockPanelTask?.cancel()
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        distributed.removeObserver(self)
        lockObservers.forEach {
            workspace.removeObserver($0)
        }
        if let lockSpaceID {
            CGSSpaceDestroy(CGSMainConnectionID(), lockSpaceID)
        }
        if let obs = stateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
