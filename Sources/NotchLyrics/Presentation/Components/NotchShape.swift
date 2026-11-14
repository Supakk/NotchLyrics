import SwiftUI

/// Native contour: a continuous lower body and two outward menu-bar shoulders.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let bottom = min(max(0, bottomRadius), rect.width / 2, rect.height)
        let top = max(0, min(topRadius, 24, rect.height - bottom))
        var path = UnevenRoundedRectangle(bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, style: .continuous).path(in: rect)
        guard top > 0 else { return path }
        let left = CGRect(x: rect.minX - 2 * top, y: rect.minY, width: 2 * top, height: 2 * top)
        let right = CGRect(x: rect.maxX, y: rect.minY, width: 2 * top, height: 2 * top)
        path.addPath(Path(left).subtracting(UnevenRoundedRectangle(topTrailingRadius: top, style: .continuous).path(in: left)))
        path.addPath(Path(right).subtracting(UnevenRoundedRectangle(topLeadingRadius: top, style: .continuous).path(in: right)))
        return path
    }
}
