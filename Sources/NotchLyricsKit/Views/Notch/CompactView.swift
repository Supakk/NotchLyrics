import SwiftUI

struct CompactView: View {
    let appState: AppState
    static var morph: Animation { NotchMotion.playbackSymbolMorph }

    private var waveformVisible: Bool {
        !appState.isTucked && appState.notchState == .compact && appState.currentTrack.hasTrack
    }
    static var swap: AnyTransition { NotchMotion.playbackSymbolSwap }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 35)
            Spacer(minLength: 0)
            // Waveform normally; right after a click it shows the play or pause symbol.
            ZStack {
                if let symbol = appState.compactRightSymbol {
                    SwappingSymbol(name: symbol, size: 12, weight: .bold)
                        .transition(Self.swap)
                } else {
                    // Animate only while the closed notch is actually showing.
                    CompactWaveform(isPlaying: appState.isPlaying && waveformVisible, colors: appState.presentationColors)
                        .transition(Self.swap)
                }
            }
            // The notch surface turns animations off for its content; this one opts back in.
            .animation(Self.morph, value: appState.compactRightSymbol)
            .frame(width: 20).padding(.trailing, appState.hasPhysicalNotch ? 7.5 : 7)
            .frame(width: 35, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            GeometryReader { geometry in
                Capsule().fill(LinearGradient(colors: appState.presentationColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geometry.size.width * appState.mediaEngine.progress), height: 2)
                    .animation(.linear(duration: 0.5), value: appState.mediaEngine.progress)
            }.frame(height: 2).padding(.horizontal, 10)
            // Only while the pointer is over the closed notch.
            .opacity(appState.compactHoverActive ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: appState.compactHoverActive)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(appState.presentationTrack.title), \(appState.presentationTrack.artist)")
    }
}
