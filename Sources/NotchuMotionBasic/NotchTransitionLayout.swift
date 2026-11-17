import CoreGraphics

/// Interpolates the frame and artwork between the closed and open notch.
public struct NotchTransitionLayout {
    public let progress: CGFloat
    public let size: CGSize
    public let artwork: CGRect

    public init(compact: CGSize, expanded: CGSize, compactArtwork: CGFloat, compactLeading: CGFloat, progress: CGFloat) {
        let t = min(1, max(0, progress))
        self.progress = t
        func mix(_ start: CGFloat, _ end: CGFloat) -> CGFloat { start + (end - start) * t }
        size = CGSize(width: mix(compact.width, expanded.width), height: mix(compact.height, expanded.height))
        let artSize = mix(compactArtwork, NotchGeometry.expandedArtworkSize)
        artwork = CGRect(
            x: mix(compactLeading, NotchGeometry.expandedArtworkLeading),
            y: mix((compact.height - compactArtwork) / 2, compact.height + NotchGeometry.expandedArtworkTopSpacing),
            width: artSize,
            height: artSize
        )
    }

    public func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat { start + (end - start) * progress }
}
