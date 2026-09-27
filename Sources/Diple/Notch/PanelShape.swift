import SwiftUI

struct PanelShape: Shape {
    var flare: CGFloat

    var base: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(flare, base) }
        set { flare = newValue.first; base = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let f = max(0, min(flare, w / 2, h / 2))
        let b = max(0, min(base, (w - f * 2) / 2, h - f))

        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))

        p.addQuadCurve(to: CGPoint(x: w - f, y: f),
                       control: CGPoint(x: w - f, y: 0))

        p.addLine(to: CGPoint(x: w - f, y: h - b))
        p.addQuadCurve(to: CGPoint(x: w - f - b, y: h),
                       control: CGPoint(x: w - f, y: h))

        p.addLine(to: CGPoint(x: f + b, y: h))
        p.addQuadCurve(to: CGPoint(x: f, y: h - b),
                       control: CGPoint(x: f, y: h))

        p.addLine(to: CGPoint(x: f, y: f))

        p.addQuadCurve(to: CGPoint(x: 0, y: 0),
                       control: CGPoint(x: f, y: 0))

        p.closeSubpath()
        return p
    }
}
