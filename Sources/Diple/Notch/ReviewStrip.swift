import SwiftUI
import AppKit

struct ReviewStrip: View {
    let tick: ReviewTick
    let start: Date
    let wings: Wings
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var eyeBesideCount = true

    static let drawer: CGFloat = 22
    static let length = 1.8
    static let paperLeaves = 0.2
    static let paperLands = 0.85
    static let barInset: CGFloat = 12

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

    static func layout(wings: Wings, notchWidth: CGFloat, notchHeight: CGFloat, eyeBesideCount: Bool = true) -> Layout {
        let width = wings.left + notchWidth + wings.right
        let rowY = notchHeight + drawer / 2 - 2
        let countX: CGFloat = wings.crowded ? wings.left / 2 + (eyeBesideCount ? 10.5 : 0)
            : wings.countOnLeft ? wings.left / 2
            : width - wings.right / 2
        return Layout(
            count: CGPoint(x: countX, y: notchHeight / 2),
            drawer: CGPoint(x: width - drawerColumn / 2 - 5, y: rowY + 1),
            number: CGPoint(x: width - drawerColumn / 2 + 11, y: rowY),
            rowY: rowY,
            cutout: wings.left...(wings.left + notchWidth)
        )
    }

    private var width: CGFloat { wings.left + notchWidth + wings.right }

    private var laid: Layout {
        Self.layout(wings: wings, notchWidth: notchWidth, notchHeight: notchHeight, eyeBesideCount: eyeBesideCount)
    }

    static let drawerColumn: CGFloat = 44
    static let drawerSize = CGSize(width: 18, height: 12)
    static let frontHeight: CGFloat = 7
    static let barGap: CGFloat = 8

    static func barSpan(width: CGFloat) -> ClosedRange<CGFloat> {
        barInset...max(barInset, width - drawerColumn - barGap)
    }

    static func sheets(for today: Int) -> Int {
        switch today {
        case ..<1: 0
        case 1...2: 1
        case 3...6: 2
        case 7...14: 3
        default: 4
        }
    }

    static func opening(at t: Double) -> Double {
        if t < paperLeaves { return 0 }
        if t < paperLeaves + 0.25 { return ease((t - paperLeaves) / 0.25) }
        if t < paperLands { return 1 }
        return 1 - clamp((t - paperLands) / 0.08)
    }

    static func shake(at t: Double) -> CGFloat {
        let b = t - (paperLands + 0.08)
        guard b > 0, b < 0.35 else { return 0 }
        return CGFloat(1.4 * sin(b * 60) * (1 - b / 0.35))
    }

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
            bar(Self.fill(at: t, reducedMotion: reducedMotion), glow: Self.glow(at: t))
                .offset(x: Self.barInset, y: notchHeight + Self.drawer - 6)
                .opacity(shown)
            drawerBack(t)
                .opacity(shown)
            number(t)
                .position(numberAt)
                .opacity(shown)
            if !reducedMotion, t >= Self.paperLeaves, t <= Self.paperLands + 0.08 {
                paper(Self.clamp((t - Self.paperLeaves) / (Self.paperLands - Self.paperLeaves)))
            }
            drawerFront(t)
                .opacity(shown)
        }
        .frame(width: width, alignment: .topLeading)
    }

    private static func inOut(_ t: Double) -> Double {
        let enter = min(1, t / 0.15)
        let leave = 1 - clamp((t - (length - 0.2)) / 0.2)
        return enter * leave
    }

    private func drawerBack(_ t: Double) -> some View {
        let size = Self.drawerSize
        let shown = Self.sheets(for: Self.today(tick, at: t, reducedMotion: reducedMotion))
        let landed = Self.clamp((t - Self.paperLands) / 0.15)
        return ZStack(alignment: .bottom) {
            DrawerBack()
            VStack(spacing: 1.1) {
                ForEach(0..<shown, id: \.self) { i in
                    let newest = i == 0 && shown > Self.sheets(for: tick.today - 1)
                    Capsule()
                        .fill(Color(white: 0.94))
                        .frame(width: size.width - 5 - CGFloat(i % 2), height: 1.1)
                        .opacity(newest ? landed : 1)
                }
            }
            .padding(.bottom, Self.frontHeight - 1)
        }
        .frame(width: size.width, height: size.height)
        .offset(x: Self.shake(at: t))
        .position(drawerAt)
    }

    private func drawerFront(_ t: Double) -> some View {
        let size = Self.drawerSize
        let slide = CGFloat(Self.opening(at: t)) * 2.5
        return DrawerFront()
            .frame(width: size.width, height: Self.frontHeight)
            .offset(x: Self.shake(at: t), y: slide)
            .position(x: drawerAt.x, y: drawerAt.y + (size.height - Self.frontHeight) / 2)
    }

    private func row(_ t: Double) -> some View {
        HStack(spacing: 0) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 4)
            Color.clear.frame(width: Self.drawerColumn)
        }
        .padding(.bottom, 6)
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
        let span = Self.barSpan(width: width)
        let length = span.upperBound - span.lowerBound
        let filled: CGFloat = max(2, length * CGFloat(p))
        let tint = tick.verdict.color
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.1))
            Capsule().fill(tint).frame(width: filled)
                .shadow(color: tint.opacity(0.9 * glow), radius: 5 * glow)
        }
        .frame(width: length, height: 2.5)
        .scaleEffect(y: 1 + 0.6 * CGFloat(glow))
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
                    Capsule().fill(.white.opacity(0.75)).frame(width: 6, height: 1.3)
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
