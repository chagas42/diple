import SwiftUI
import AppKit

struct ReviewStrip: View {
    let tick: ReviewTick
    let start: Date
    let width: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let countOnLeft: Bool

    static let drawer: CGFloat = 20
    static let length = 1.8
    static let paperLeaves = 0.2
    static let paperLands = 0.85
    static let barWidth: CGFloat = 34

    static func shortPR(_ key: String) -> String {
        let parts = key.split(separator: "/")
        return parts.count > 1 ? String(parts[1]) : key
    }

    static func today(_ t: ReviewTick, at elapsed: Double, reducedMotion: Bool = false) -> Int {
        reducedMotion || elapsed >= paperLands ? t.today : t.today - 1
    }

    static func fill(at elapsed: Double, reducedMotion: Bool = false) -> Double {
        if reducedMotion { return 1 }
        return ease(clamp((elapsed - paperLeaves) / (paperLands - paperLeaves)))
    }

    static func glow(at elapsed: Double) -> Double {
        let b = (elapsed - paperLands) / 0.35
        guard b > 0, b < 1 else { return 0 }
        return sin(b * .pi)
    }

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    private let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    struct Layout {
        let count: CGPoint
        let drawer: CGPoint
        let number: CGPoint
        let rowY: CGFloat
        let cutout: ClosedRange<CGFloat>
    }

    static func layout(width: CGFloat, notchWidth: CGFloat, notchHeight: CGFloat, countOnLeft: Bool) -> Layout {
        let column = countOnLeft ? max(0, width - notchWidth) : max(0, (width - notchWidth) / 2)
        let rowY = notchHeight + drawer / 2 - 1
        let start = column
        return Layout(
            count: CGPoint(x: countOnLeft ? column / 2 : width - column / 2, y: notchHeight / 2),
            drawer: CGPoint(x: width - drawerColumn / 2 - 6, y: rowY + 1),
            number: CGPoint(x: width - drawerColumn / 2 + 9, y: rowY),
            rowY: rowY,
            cutout: start...max(start, start + notchWidth)
        )
    }

    private var laid: Layout {
        Self.layout(width: width, notchWidth: notchWidth, notchHeight: notchHeight, countOnLeft: countOnLeft)
    }

    static let drawerColumn: CGFloat = 40

    private var countAt: CGPoint { laid.count }
    private var rowY: CGFloat { laid.rowY }
    private var drawerAt: CGPoint { laid.drawer }
    private var numberAt: CGPoint { laid.number }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            frame(t)
        }
        .allowsHitTesting(false)
    }

    private func frame(_ t: Double) -> some View {
        let shown = Self.inOut(t)
        return ZStack(alignment: .topLeading) {
            row(t)
                .frame(width: width, height: Self.drawer)
                .offset(y: notchHeight)
                .opacity(shown)
            DrawerBack()
                .frame(width: 15, height: 10)
                .position(drawerAt)
                .opacity(shown)
            number(t)
                .position(numberAt)
                .opacity(shown)
            if !reducedMotion, t >= Self.paperLeaves, t <= Self.paperLands + 0.08 {
                paper(Self.clamp((t - Self.paperLeaves) / (Self.paperLands - Self.paperLeaves)))
            }
            DrawerFront()
                .frame(width: 15, height: 6)
                .offset(y: Self.jolt(t))
                .position(x: drawerAt.x, y: drawerAt.y + 2.5)
                .opacity(shown)
        }
        .frame(width: width, alignment: .topLeading)
    }

    private static func inOut(_ t: Double) -> Double {
        let enter = min(1, t / 0.15)
        let leave = 1 - clamp((t - (length - 0.2)) / 0.2)
        return enter * leave
    }

    private static func jolt(_ t: Double) -> CGFloat {
        let b = (t - paperLands) / 0.22
        guard b > 0, b < 1 else { return 0 }
        return CGFloat(1.4 * sin(b * .pi))
    }

    private func row(_ t: Double) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                label
                Spacer(minLength: 4)
                bar(Self.fill(at: t, reducedMotion: reducedMotion), glow: Self.glow(at: t))
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            Color.clear.frame(width: Self.drawerColumn)
        }
        .padding(.bottom, 2)
    }

    private var label: some View {
        HStack(spacing: 5) {
            Text("\u{203A}")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(tick.verdict.color)
            Text(tick.verdict.short)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(tick.verdict.color)
            Text(Self.shortPR(tick.pr))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func bar(_ p: Double, glow: Double) -> some View {
        let filled: CGFloat = max(2, Self.barWidth * CGFloat(p))
        let tint = tick.verdict.color
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))
            Capsule().fill(tint).frame(width: filled)
                .shadow(color: tint.opacity(0.9 * glow), radius: 4 * glow)
        }
        .frame(width: Self.barWidth, height: 3)
        .scaleEffect(y: 1 + 0.5 * CGFloat(glow))
    }

    private func number(_ t: Double) -> some View {
        let n = Self.today(tick, at: t, reducedMotion: reducedMotion)
        let b = (t - Self.paperLands) / 0.3
        let bump: CGFloat = b > 0 && b < 1 ? CGFloat(sin(b * .pi)) : 0
        return Text("\(n)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.92))
            .contentTransition(.numericText(value: Double(n)))
            .animation(.snappy(duration: 0.25), value: n)
            .scaleEffect(1 + 0.3 * bump)
    }

    struct Flight {
        let point: CGPoint
        let angle: Double
        let scale: CGFloat
        let opacity: Double
    }

    static let nearby: CGFloat = 30

    static func flight(_ p: Double, from: CGPoint, to: CGPoint, glide: CGFloat) -> Flight {
        let grow = 0.75 + 0.35 * sin(p * .pi)
        let fade = p < 0.15 ? p / 0.15 : (p > 0.9 ? max(0, (1 - p) / 0.1) : 1)
        let point = abs(to.x - from.x) < nearby ? hop(p, from: from, to: to) : across(p, from: from, to: to, glide: glide)
        let lean = to.x < from.x ? -1.0 : 1.0
        return Flight(point: point, angle: lean * (-18 + 26 * ease(p)), scale: CGFloat(grow), opacity: fade)
    }

    private static func hop(_ p: Double, from: CGPoint, to: CGPoint) -> CGPoint {
        let e = ease(p)
        let x = Double(from.x) + Double(to.x - from.x) * e
        let y = Double(from.y) + Double(to.y - from.y) * e - 7 * sin(p * .pi)
        return CGPoint(x: x, y: y)
    }

    private static func across(_ p: Double, from: CGPoint, to: CGPoint, glide: CGFloat) -> CGPoint {
        let side: Double = to.x > from.x ? 1 : -1
        let drop = 0.35
        let nudge = 8 * side
        if p < drop {
            let q = p / drop
            let out = 1 - (1 - q) * (1 - q)
            return CGPoint(x: Double(from.x) + nudge * q, y: Double(from.y) + Double(glide - from.y) * out)
        }
        let q = (p - drop) / (1 - drop)
        let startX = Double(from.x) + nudge
        let x = startX + (Double(to.x) - startX) * ease(q)
        let y = Double(glide) - 2 * sin(q * .pi) + Double(to.y - glide) * q * q * q
        return CGPoint(x: x, y: y)
    }

    private func paper(_ p: Double) -> some View {
        let to = CGPoint(x: drawerAt.x, y: drawerAt.y + 1)
        let f = Self.flight(p, from: countAt, to: to, glide: rowY)
        return Paper(tint: tick.verdict.color)
            .frame(width: 10, height: 13)
            .scaleEffect(f.scale)
            .rotationEffect(.degrees(f.angle))
            .opacity(f.opacity)
            .position(f.point)
    }

    private struct DrawerBack: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(white: 0.16))
                .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
        }
    }

    private struct DrawerFront: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(white: 0.34))
                .overlay(
                    Capsule().fill(.white.opacity(0.75)).frame(width: 5, height: 1.2)
                )
                .shadow(color: .black.opacity(0.4), radius: 0.8, y: -0.5)
        }
    }

    private struct Paper: View {
        let tint: Color

        var body: some View {
            ZStack(alignment: .topLeading) {
                Folded().fill(Color(white: 0.96))
                Folded().stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                VStack(alignment: .leading, spacing: 1.8) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(i == 0 ? tint : Color.black.opacity(0.22))
                            .frame(width: i == 2 ? 4 : 6, height: 1.2)
                    }
                }
                .padding(.leading, 2)
                .padding(.top, 4)
            }
            .shadow(color: .black.opacity(0.45), radius: 1.2, y: 0.8)
        }
    }

    private struct Folded: Shape {
        func path(in r: CGRect) -> Path {
            let f = r.width * 0.3
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - f, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + f))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
            return p
        }
    }
}
