import SwiftUI

struct PanelShape: Shape {
    var flare: CGFloat

    var base: CGFloat

    var pull = Pull.none

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, Pull> {
        get { .init(.init(flare, base), pull) }
        set { flare = newValue.first.first; base = newValue.first.second; pull = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        if !pull.isNone, flare < 0.5 {
            let b = max(0, min(base, r.width / 2, r.height))
            let outline = Blob.outline(width: r.width, height: r.height, radius: b)
            return Blob.path(through: Blob.drawn(outline, height: r.height, toward: pull))
        }
        let x0: CGFloat = 0, x1 = r.width
        let w = x1 - x0, h = r.height
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

        let flatFrom = x0 + f + b
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
