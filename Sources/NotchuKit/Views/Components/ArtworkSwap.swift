import AppKit
import SwiftUI

/// Shows a cover and animates changes between covers. The outgoing cover turns away while
/// the incoming one turns in; a cover that arrives during a change waits in a single queued
/// slot (replacing any earlier one), so fast skipping goes straight to the latest cover.
/// Fills the frame it is given.
struct ArtworkSwap: View {
    let image: NSImage?
    var placeholderSymbolSize: CGFloat = 20

    @State private var current: NSImage?
    @State private var outgoing: NSImage?
    @State private var queued: NSImage??
    @State private var changing = false
    @State private var outProgress: Double = 1
    @State private var inProgress: Double = 1
    @State private var glow: Double = 0
    @State private var settleTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if changing {
                cover(outgoing)
                    .rotation3DEffect(.degrees(outProgress * NotchMotion.artworkFlipDegrees), axis: (0, 1, 0), perspective: 0.6)
                    .opacity(1 - outProgress)
            }
            cover(current)
                .overlay(Color.white.opacity(glow))
                .rotation3DEffect(.degrees((inProgress - 1) * NotchMotion.artworkFlipDegrees), axis: (0, 1, 0), perspective: 0.6)
                .opacity(changing ? inProgress : 1)
        }
        .onAppear { current = image }
        .onChange(of: image.map(ObjectIdentifier.init)) { _, _ in show(image) }
        .onDisappear { settleTask?.cancel() }
    }

    private func show(_ next: NSImage?) {
        if changing { queued = .some(next); return }
        changing = true
        outgoing = current
        current = next
        outProgress = 0
        inProgress = 0
        glow = NotchMotion.artworkGlowStart
        withAnimation(NotchMotion.artworkOut) { outProgress = 1 }
        withAnimation(NotchMotion.artworkIn.delay(NotchMotion.artworkInDelay)) { inProgress = 1 }
        withAnimation(NotchMotion.artworkGlow.delay(NotchMotion.artworkInDelay)) { glow = 0 }
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: NotchMotion.artworkSettle)
            guard !Task.isCancelled else { return }
            changing = false
            outgoing = nil
            if let waiting = queued {
                queued = nil
                if waiting !== current { show(waiting) }
            }
        }
    }

    @ViewBuilder private func cover(_ image: NSImage?) -> some View {
        if let image {
            Color.clear.overlay {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
            .clipped()
        } else {
            LinearGradient(colors: [Color(white: 0.35), Color(white: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: placeholderSymbolSize))
                        .foregroundStyle(.white.opacity(0.8))
                }
        }
    }
}
