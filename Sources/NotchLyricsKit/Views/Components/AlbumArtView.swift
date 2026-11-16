import SwiftUI

/// Displays album artwork with a gradient and music symbol as a fallback.
struct AlbumArtView: View {
    let image: NSImage?
    var size: CGFloat = 56
    var cornerRadius: CGFloat? = nil

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback gradient
                LinearGradient(
                    colors: [Color(white: 0.35), Color(white: 0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.15, style: .continuous))
    }
}
