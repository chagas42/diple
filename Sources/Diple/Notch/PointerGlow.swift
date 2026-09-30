import SwiftUI

struct Glow: Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rim: CGFloat = 0
    var spill: CGFloat = 0
    var depth: CGFloat = 0

    static let off = Glow()
    static let approach: CGFloat = 40

    var isOn: Bool { max(rim, spill) > 0.01 }

    static func target(pointer p: CGPoint, cutout c: CGRect) -> Glow {
        guard c.width > 0 else { return .off }
        let local = (x: p.x - c.midX, y: c.maxY - p.y)
        if (c.minX...c.maxX).contains(p.x), p.y >= c.minY {
            let fromEdge = min(p.x - c.minX, c.maxX - p.x, p.y - c.minY)
            let depth = min(1, max(0, (p.y - c.minY) / c.height))
            return Glow(x: local.x, y: local.y, rim: 0.6 + 0.25 * depth, spill: 1, depth: fromEdge)
        }
        let dx = max(c.minX - p.x, 0, p.x - c.maxX)
        let dy = max(c.minY - p.y, 0, p.y - c.maxY)
        let near = 1 - min(1, hypot(dx, dy) / approach)
        guard near > 0 else { return .off }
        return Glow(x: local.x, y: local.y, rim: 0.6 * near * near * (3 - 2 * near), spill: 0)
    }
}

@MainActor
final class GlowState: ObservableObject {
    @Published private(set) var glow = Glow.off

    func show(_ next: Glow) {
        guard next != glow else { return }
        if next.isOn, !glow.isOn {
            glow = Glow(x: next.x, y: next.y)
        }
        glow = next.isOn ? next : Glow(x: glow.x, y: glow.y, depth: glow.depth)
    }
}

struct CutoutRim: Shape {
    let cutout: CGSize
    var corner: CGFloat = 9
    var outset: CGFloat = 1.5

    func path(in r: CGRect) -> Path {
        let w = cutout.width + outset * 2, h = cutout.height + outset
        let x0 = r.midX - w / 2, x1 = r.midX + w / 2
        let c = min(corner + outset, w / 2, h)
        var p = Path()
        p.move(to: CGPoint(x: x0, y: 0))
        p.addLine(to: CGPoint(x: x0, y: h - c))
        p.addQuadCurve(to: CGPoint(x: x0 + c, y: h), control: CGPoint(x: x0, y: h))
        p.addLine(to: CGPoint(x: x1 - c, y: h))
        p.addQuadCurve(to: CGPoint(x: x1, y: h - c), control: CGPoint(x: x1, y: h))
        p.addLine(to: CGPoint(x: x1, y: 0))
        return p
    }
}

struct PointerGlowView: View {
    @ObservedObject var state: GlowState
    let width: CGFloat
    let height: CGFloat
    let cutout: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let light = Color(red: 1, green: 0.97, blue: 0.92)
    private static let reach: CGFloat = 70
    private static let spread: CGFloat = 55

    var body: some View {
        let g = state.glow
        let rim = CutoutRim(cutout: cutout)
        let source = UnitPoint(x: (width / 2 + g.x) / width, y: g.y / height)
        let lit = RadialGradient(colors: [Self.light, Self.light.opacity(0.35), .clear],
                                 center: source, startRadius: 0, endRadius: Self.reach + g.depth)
        let spill = RadialGradient(colors: [Self.light.opacity(0.09), Self.light.opacity(0.03), .clear],
                                   center: source, startRadius: g.depth, endRadius: Self.spread + g.depth)
        ZStack {
            Rectangle().fill(spill)
                .opacity(g.spill)
                .animation(.easeOut(duration: 0.25), value: g.spill)
            Group {
                rim.stroke(lit, style: StrokeStyle(lineWidth: 5, lineCap: .round)).blur(radius: 4).opacity(0.16)
                rim.stroke(lit, style: StrokeStyle(lineWidth: 1, lineCap: .round)).opacity(0.3)
            }
            .opacity(g.rim)
            .animation(.easeOut(duration: 0.12), value: g.rim)
        }
        .frame(width: width, height: height)
        .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.9), value: CGPoint(x: g.x, y: g.y))
        .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.9), value: g.depth)
        .allowsHitTesting(false)
    }
}
