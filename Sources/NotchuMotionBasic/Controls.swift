import AppKit
import SwiftUI

/// Plain button feel: fixed size for playback controls and a dim while pressed.
public struct MediaControlStyle: ButtonStyle {
    public var cornerRadius: CGFloat
    public var playbackControl: Bool
    public var blackBackground: Bool
    public var onPressChange: ((Bool) -> Void)?

    public init(cornerRadius: CGFloat = 16, playbackControl: Bool = false, blackBackground: Bool = false, onPressChange: ((Bool) -> Void)? = nil) {
        self.cornerRadius = cornerRadius
        self.playbackControl = playbackControl
        self.blackBackground = blackBackground
        self.onPressChange = onPressChange
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: playbackControl ? 38 : nil, height: playbackControl ? 38 : nil)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, down in onPressChange?(down) }
    }
}

/// Playback symbol.
public struct SwappingSymbol: View {
    let name: String
    let size: CGFloat
    let weight: Font.Weight
    let opacity: Double

    public init(name: String, size: CGFloat, weight: Font.Weight, opacity: Double = 1) {
        self.name = name
        self.size = size
        self.weight = weight
        self.opacity = opacity
    }

    public var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.white.opacity(opacity))
            .frame(width: 26, height: 26)
    }
}

/// Activity indicator for the closed notch.
public struct CompactWaveform: View {
    let isPlaying: Bool
    let colors: [Color]

    public init(isPlaying: Bool, colors: [Color]) {
        self.isPlaying = isPlaying
        self.colors = colors
    }

    public var body: some View {
        Image(systemName: isPlaying ? "waveform" : "pause.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

/// Single-line title, truncated when it does not fit.
public struct MarqueeText: View {
    let text: String
    let fontSize: CGFloat
    let weight: NSFont.Weight
    let color: NSColor

    public init(text: String, fontSize: CGFloat = 14, weight: NSFont.Weight = .semibold, color: NSColor = .white, isActive: Bool = true) {
        self.text = text
        self.fontSize = fontSize
        self.weight = weight
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(Font(NSFont.systemFont(ofSize: fontSize, weight: weight)))
            .foregroundStyle(Color(nsColor: color))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
