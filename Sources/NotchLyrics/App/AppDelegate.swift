import AppKit
import SwiftUI
import ServiceManagement

/// Manages the menu bar item, window lifecycle, and mouse tracking.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController!
    private var statusItem: NSStatusItem!
    private let appState = AppState()
    private var lockPanel: NSPanel?
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
        let center = DistributedNotificationCenter.default()
        lockObservers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self, UserDefaults.standard.bool(forKey: "lockLyricsEnabled"), let screen = NSScreen.screens.first else { return }
            let panel = NSPanel(contentRect: NSRect(x: screen.frame.midX - 170, y: screen.frame.minY + 100, width: 340, height: 320), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.canBecomeVisibleWithoutLogin = true
            panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: LockLyricsView(state: self.appState))
            self.appState.lockLyrics.load(self.appState.currentTrack)
            self.lockPanel = panel
            panel.orderFrontRegardless()
        })
        lockObservers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.lockPanel?.orderOut(nil)
            self?.lockPanel = nil
        })
    }

    @objc private func toggleLockLyrics(_ sender: NSMenuItem) {
        let enabled = !UserDefaults.standard.bool(forKey: "lockLyricsEnabled")
        UserDefaults.standard.set(enabled, forKey: "lockLyricsEnabled")
        sender.state = enabled ? .on : .off
        if !enabled { lockPanel?.orderOut(nil); lockPanel = nil }
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
        lyricsItem.state = UserDefaults.standard.bool(forKey: "lockLyricsEnabled") ? .on : .off
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
        if let obs = stateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
