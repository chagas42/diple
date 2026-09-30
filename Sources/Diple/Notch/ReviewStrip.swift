import SwiftUI
import AppKit

struct ReviewStrip: View {
    let tick: ReviewTick
    let start: Date
    let total: Int
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

    static func fill(_ t: ReviewTick, total: Int, at elapsed: Double, reducedMotion: Bool = false) -> Double {
        guard total > 0 else { return 1 }
        let before = Double(max(0, t.today - 1)) / Double(total)
        let after = min(1, Double(t.today) / Double(total))
        if reducedMotion { return after }
        let p = ease(clamp((elapsed - paperLands) / 0.3))
        return before + (after - before) * p
    }

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    private let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var column: CGFloat {
        countOnLeft ? max(0, width - notchWidth) : max(0, (width - notchWidth) / 2)
    }

    private var columnX: CGFloat { countOnLeft ? column / 2 : width - column / 2 }
    private var rowY: CGFloat { notchHeight + Self.drawer / 2 - 1 }
    private var drawerAt: CGPoint { CGPoint(x: columnX - 6, y: rowY + 1) }
    private var numberAt: CGPoint { CGPoint(x: columnX + 9, y: rowY) }

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
            if countOnLeft { Color.clear.frame(width: column) }
            HStack(spacing: 5) {
                label
                Spacer(minLength: 4)
                bar(Self.fill(tick, total: total, at: t, reducedMotion: reducedMotion))
            }
            .padding(.leading, countOnLeft ? 4 : 12)
            .padding(.trailing, countOnLeft ? 12 : 4)
            if !countOnLeft { Color.clear.frame(width: column) }
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

    private func bar(_ p: Double) -> some View {
        let filled: CGFloat = max(2, Self.barWidth * CGFloat(p))
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))
            Capsule().fill(tick.verdict.color).frame(width: filled)
        }
        .frame(width: Self.barWidth, height: 3)
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

    static func flight(_ p: Double, from: CGPoint, to: CGPoint) -> Flight {
        let e = ease(p)
        let dx = Double(to.x - from.x)
        let dy = Double(to.y - from.y)
        let hop = 7 * sin(p * .pi)
        let x = Double(from.x) + dx * e
        let y = Double(from.y) + dy * e - hop
        let grow = 0.75 + 0.35 * sin(p * .pi)
        let fade = p < 0.15 ? p / 0.15 : (p > 0.9 ? max(0, (1 - p) / 0.1) : 1)
        return Flight(point: CGPoint(x: x, y: y), angle: -18 + 26 * e, scale: CGFloat(grow), opacity: fade)
    }

    private func paper(_ p: Double) -> some View {
        let from = CGPoint(x: columnX, y: notchHeight / 2)
        let to = CGPoint(x: drawerAt.x, y: drawerAt.y + 1)
        let f = Self.flight(p, from: from, to: to)
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
