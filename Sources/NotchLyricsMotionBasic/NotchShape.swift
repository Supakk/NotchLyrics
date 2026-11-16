import SwiftUI

/// Notch outline: a rectangle with rounded bottom corners.
public struct NotchShape: Shape {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat

    public init(topRadius: CGFloat, bottomRadius: CGFloat) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    public func path(in rect: CGRect) -> Path {
        let bottom = min(max(0, bottomRadius), rect.width / 2, rect.height)
        return UnevenRoundedRectangle(bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, style: .continuous).path(in: rect)
    }
}

/// Black notch fill.
public struct NotchCornerMask: View, Animatable {
    let compact: (top: CGFloat, bottom: CGFloat)
    let expanded: (top: CGFloat, bottom: CGFloat)
    public var progress: CGFloat

    public init(compact: (top: CGFloat, bottom: CGFloat), expanded: (top: CGFloat, bottom: CGFloat), progress: CGFloat) {
        self.compact = compact
        self.expanded = expanded
        self.progress = progress
    }

    public var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    public var body: some View {
        NotchShape(topRadius: 0, bottomRadius: compact.bottom + (expanded.bottom - compact.bottom) * progress)
            .fill(.black)
    }
}
