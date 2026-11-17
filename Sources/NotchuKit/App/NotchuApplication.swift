import AppKit

/// Entry point used by the `Notchu` executable.
public enum NotchuApplication {
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
