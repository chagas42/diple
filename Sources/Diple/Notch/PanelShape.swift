import SwiftUI

struct PanelShape: Shape {
    var flare: CGFloat

    var base: CGFloat

    var pull: CGFloat = 0

    var pullCenter: CGFloat = 0

    var pullHalfWidth: CGFloat = 52

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(flare, base), .init(pull, pullCenter)) }
        set {
            flare = newValue.first.first; base = newValue.first.second
            pull = newValue.second.first; pullCenter = newValue.second.second
        }
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

        let flatFrom = f + b, flatTo = w - f - b
        let half = min(pullHalfWidth, (flatTo - flatFrom) / 2)
        let depth = max(0, pull)
        if depth > 0.05, half > 4 {
            let cx = min(max(w / 2 + pullCenter, flatFrom + half), flatTo - half)
            p.addLine(to: CGPoint(x: cx + half, y: h))
            p.addCurve(to: CGPoint(x: cx, y: h + depth),
                       control1: CGPoint(x: cx + half * 0.45, y: h),
                       control2: CGPoint(x: cx + half * 0.55, y: h + depth))
            p.addCurve(to: CGPoint(x: cx - half, y: h),
                       control1: CGPoint(x: cx - half * 0.55, y: h + depth),
                       control2: CGPoint(x: cx - half * 0.45, y: h))
        }
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
