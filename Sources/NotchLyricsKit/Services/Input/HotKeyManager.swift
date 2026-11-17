import AppKit
import Carbon

/// Manages system-wide keyboard shortcuts.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    private init() {
        installHandler()
    }

    /// Register a keyboard shortcut.
    /// - Parameters:
    /// - keyCode: Virtual key code, such as kVK_ANSI_L (37).
    /// - modifiers: Modifier flags, such as cmdKey | shiftKey.
    /// - handler: Closure called when the shortcut is pressed.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1

        var hotKeyID = EventHotKeyID(signature: FourCharCode(1397966180), id: id) // 'NLYR'
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            handlers[id] = handler
            print("[HotKey] Registered hotkey #\(id)")
        } else {
            print("[HotKey] Failed to register hotkey: \(status)")
        }

        return id
    }

    /// Register Command-Shift-L to toggle lyrics.
    func registerDefaults(appState: AppState) {
        // ⌘+Shift+N = Toggle expand
        register(
            keyCode: 45, // kVK_ANSI_N
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak appState] in
            appState?.toggleExpanded()
        }
    }

    // MARK: - Carbon event handler

    private func installHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                HotKeyManager.shared.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventSpec,
            nil,
            nil
        )
    }
}
