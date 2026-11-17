import SwiftUI

/// Basic motion and look for the lock-screen player (same API as the private package).
public enum LockMotion {
    public static let appear = Animation.easeOut(duration: 0.3)
    public static let disappear = Animation.easeOut(duration: 0.3)
    public static let hiddenScale: CGFloat = 1
    public static let hiddenBlur: CGFloat = 0

    public static let modeSwitch = Animation.easeInOut(duration: 0.35)
    public static var lyricsTransition: AnyTransition { .opacity }

    public static let lyricLead: TimeInterval = 0
    public static let readingLine: CGFloat = 0.4
    public static let lineFocus = Animation.easeInOut(duration: 0.3)
    public static let lyricScroll = Animation.easeInOut(duration: 0.4)
    public static let ripple: Double = 0
    public static let rippleLines = 0
    public static let focusScale: CGFloat = 1
    public static func lineBlur(distance: Int) -> CGFloat { 0 }
    public static func interludeWave(time: TimeInterval, index: Int) -> Double { 0.5 }

    public static let coverBlurRadius: Double = 10
    public static let coverSaturation: Double = 1
    public static let coverOpacity: Double = 0.5
    public static let panelDim: Double = 0.25
    public static let coverChange = Animation.easeInOut(duration: 0.5)
}

extension NotchMotion {
    public static var playbackSymbolSwap: AnyTransition { .opacity }
    public static let playbackSymbolMorph = Animation.easeInOut(duration: 0.2)
}
