import CoreGraphics

/// Sizes and corner radii of the notch, closed and open.
public enum NotchGeometry {
    public static func compactSize(cameraWidth: CGFloat, topInset: CGFloat, hasActivity: Bool, hasPhysicalNotch: Bool) -> CGSize {
        CGSize(width: cameraWidth + (hasActivity ? 70 : 0), height: topInset)
    }

    public static func expandedSize(cameraWidth: CGFloat, topInset: CGFloat) -> CGSize {
        CGSize(width: min(cameraWidth + 160, 345), height: max(topInset + 142, 175))
    }

    public static func cornerRadii(hasActivity: Bool, expanded: Bool, hasPhysicalNotch: Bool = true, notchHeight: CGFloat = 34) -> (top: CGFloat, bottom: CGFloat) {
        expanded ? (16, 32) : (6, 10)
    }

    public static func hoverSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width * NotchMotion.hoverScale.width, height: size.height * NotchMotion.hoverScale.height)
    }

    public static func compactArtwork(hasPhysicalNotch: Bool) -> (size: CGFloat, leading: CGFloat) { (18, 7) }

    public static func compactArtworkCornerRadius(hasPhysicalNotch: Bool, hovering: Bool) -> CGFloat { 4 }

    public static let expandedArtworkSize: CGFloat = 44
    public static let expandedArtworkLeading: CGFloat = 20
    public static let expandedArtworkTopSpacing: CGFloat = 6
    public static let expandedArtworkCornerRadius: CGFloat = 6
}
