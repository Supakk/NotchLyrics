import AppKit

/// Entry point used by the `NotchLyrics` executable.
public enum NotchLyricsApplication {
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
