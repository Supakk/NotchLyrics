import SwiftUI

// Open, basic implementation of the NotchuMotion API. It keeps the app fully
// working with standard SwiftUI motion; the tuned version lives in a private package
// that `Package.swift` uses instead when it is checked out next to this repository.

/// Timing for the notch: open/close, content reveal, hover and press.
public enum NotchMotion {
    public static let expand = Animation.smooth(duration: 0.4)
    public static let collapse = Animation.smooth(duration: 0.3)

    public static let contentRevealDelay: Duration = .zero
    public static let contentReveal = Animation.easeOut(duration: 0.2)
    public static let hiddenContentBlur: CGFloat = 0

    public static let tuck = Animation.smooth(duration: 0.3)
    public static let untuck = Animation.smooth(duration: 0.6)

    public static func hover(active: Bool) -> Animation { .smooth(duration: 0.25) }
    public static let hoverScale = CGSize(width: 1.05, height: 1.1)

    public static let press = Animation.easeOut(duration: 0.15)
    public static let pressedScale = CGSize(width: 0.96, height: 0.94)

    public static let collapseDelay: Duration = .milliseconds(500)

    public static let iconSwap = Animation.easeInOut(duration: 0.2)

    public static func compactContentOpacity(progress: CGFloat) -> CGFloat { 1 - min(1, max(0, progress)) }
    public static func expandedContentOpacity(progress: CGFloat) -> CGFloat { min(1, max(0, progress)) }
    public static func expandedContentScale(frameWidth: CGFloat, expandedWidth: CGFloat) -> CGFloat { 1 }
}
