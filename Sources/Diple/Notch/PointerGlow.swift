import SwiftUI

struct Glow: Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var intensity: CGFloat = 0
    var onSide = false

    static let off = Glow()

    var isOn: Bool { intensity > 0.01 }

    static func target(pointer p: CGPoint, cutout c: CGRect) -> Glow {
        guard c.width > 0, c.contains(p) else { return .off }
        let left = p.x - c.minX, right = c.maxX - p.x, bottom = p.y - c.minY
        let local = CGPoint(x: p.x - c.midX, y: c.maxY - p.y)
        let edge: CGPoint
        let onSide = min(left, right) < bottom
        if !onSide {
            edge = CGPoint(x: local.x, y: c.height)
        } else if left < right {
            edge = CGPoint(x: -c.width / 2, y: local.y)
        } else {
            edge = CGPoint(x: c.width / 2, y: local.y)
        }
        let depth = min(1, max(0, bottom / c.height))
        return Glow(x: edge.x, y: edge.y, intensity: 0.6 + 0.4 * depth, onSide: onSide)
    }
}

@MainActor
final class GlowState: ObservableObject {
    @Published private(set) var glow = Glow.off

    func show(_ next: Glow) {
        guard next != glow else { return }
        if next.isOn, !glow.isOn {
            glow = Glow(x: next.x, y: next.y, intensity: 0, onSide: next.onSide)
        }
        glow = next.isOn ? next : Glow(x: glow.x, y: glow.y, intensity: 0, onSide: glow.onSide)
    }
}

struct PointerGlowView: View {
    @ObservedObject var state: GlowState
    let width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let g = state.glow
        let along: CGFloat = 88, across: CGFloat = 20
        Rectangle()
            .fill(EllipticalGradient(
                colors: [Color(red: 1, green: 0.94, blue: 0.84).opacity(0.9), .clear],
                center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
            ))
            .frame(width: g.onSide ? across : along, height: g.onSide ? along / 2 : across)
            .blur(radius: 5)
            .opacity(g.intensity)
            .position(x: width / 2 + g.x, y: g.y)
            .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.9), value: CGPoint(x: g.x, y: g.y))
            .animation(.easeOut(duration: 0.12), value: g.intensity)
            .allowsHitTesting(false)
    }
}
