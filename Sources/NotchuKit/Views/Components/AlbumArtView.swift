import SwiftUI

/// Displays album artwork with a gradient and music symbol as a fallback.
struct AlbumArtView: View {
    let image: NSImage?
    var size: CGFloat = 56
    var cornerRadius: CGFloat? = nil

    var body: some View {
        // Animates cover changes; falls back to a gradient with a music symbol.
        ArtworkSwap(image: image, placeholderSymbolSize: size * 0.35)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.15, style: .continuous))
    }
}
