import SwiftUI

struct PanelShape: Shape {
    var flare: CGFloat

    var base: CGFloat

    var pull = Pull.none

    var pullHalfWidth: CGFloat = 52

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, Pull> {
        get { .init(.init(flare, base), pull) }
        set { flare = newValue.first.first; base = newValue.first.second; pull = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let x0 = -max(0, pull.left), x1 = r.width + max(0, pull.right)
        let w = x1 - x0, h = r.height + max(0, pull.sag)
        let f = max(0, min(flare, w / 2, h / 2))
        let b = max(0, min(base, (w - f * 2) / 2, h - f))

        var p = Path()
        p.move(to: CGPoint(x: x0, y: 0))
        p.addLine(to: CGPoint(x: x1, y: 0))

        p.addQuadCurve(to: CGPoint(x: x1 - f, y: f),
                       control: CGPoint(x: x1 - f, y: 0))

        p.addLine(to: CGPoint(x: x1 - f, y: h - b))
        p.addQuadCurve(to: CGPoint(x: x1 - f - b, y: h),
                       control: CGPoint(x: x1 - f, y: h))

        let flatFrom = x0 + f + b, flatTo = x1 - f - b
        let half = min(pullHalfWidth, (flatTo - flatFrom) / 2)
        let depth = max(0, pull.bulge)
        if depth > 0.05, half > 4 {
            let cx = min(max(r.width / 2 + pull.center, flatFrom + half), flatTo - half)
            p.addLine(to: CGPoint(x: cx + half, y: h))
            p.addCurve(to: CGPoint(x: cx, y: h + depth),
                       control1: CGPoint(x: cx + half * 0.45, y: h),
                       control2: CGPoint(x: cx + half * 0.55, y: h + depth))
            p.addCurve(to: CGPoint(x: cx - half, y: h),
                       control1: CGPoint(x: cx - half * 0.55, y: h + depth),
                       control2: CGPoint(x: cx - half * 0.45, y: h))
        }
        p.addLine(to: CGPoint(x: flatFrom, y: h))
        p.addQuadCurve(to: CGPoint(x: x0 + f, y: h - b),
                       control: CGPoint(x: x0 + f, y: h))

        p.addLine(to: CGPoint(x: x0 + f, y: f))

        p.addQuadCurve(to: CGPoint(x: x0, y: 0),
                       control: CGPoint(x: x0 + f, y: 0))

        p.closeSubpath()
        return p
    }
}
