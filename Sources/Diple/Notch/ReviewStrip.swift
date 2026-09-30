import SwiftUI
import AppKit

struct ReviewStrip: View {
    let tick: ReviewTick
    let start: Date
    let width: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let countOnLeft: Bool

    static let drawer: CGFloat = 18
    static let length = 1.7
    static let paperLeaves = 0.2
    static let paperLands = 0.8

    static func shortPR(_ key: String) -> String {
        let parts = key.split(separator: "/")
        return parts.count > 1 ? String(parts[1]) : key
    }

    static func today(_ t: ReviewTick, at elapsed: Double, reducedMotion: Bool = false) -> Int {
        reducedMotion || elapsed >= paperLands ? t.today : t.today - 1
    }

    private var column: CGFloat {
        countOnLeft ? max(0, width - notchWidth) : max(0, (width - notchWidth) / 2)
    }

    private var countX: CGFloat {
        countOnLeft ? column / 2 : width - column / 2
    }

    private let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            let inOut = min(1, t / 0.15) * (1 - min(1, max(0, (t - (Self.length - 0.2)) / 0.2)))
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: notchHeight)
                    row(t)
                        .frame(height: Self.drawer)
                        .opacity(inOut)
                }
                if !reducedMotion, t >= Self.paperLeaves, t <= Self.paperLands + 0.05 {
                    paper(min(1, (t - Self.paperLeaves) / (Self.paperLands - Self.paperLeaves)))
                }
            }
            .frame(width: width, alignment: .topLeading)
        }
        .allowsHitTesting(false)
    }

    private func row(_ t: Double) -> some View {
        HStack(spacing: 0) {
            if countOnLeft {
                today(t).frame(width: column)
                label(t).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                label(t).frame(maxWidth: .infinity, alignment: .leading)
                today(t).frame(width: column)
            }
        }
        .padding(.leading, countOnLeft ? 0 : 12)
        .padding(.trailing, countOnLeft ? 12 : 0)
        .padding(.bottom, 3)
    }

    private func label(_ t: Double) -> some View {
        HStack(spacing: 5) {
            if countOnLeft { todayWord }
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
            if !countOnLeft {
                Spacer(minLength: 4)
                todayWord
            }
        }
    }

    private var todayWord: some View {
        Text("today")
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.42))
    }

    private func today(_ t: Double) -> some View {
        let n = Self.today(tick, at: t, reducedMotion: reducedMotion)
        let b = (t - Self.paperLands) / 0.3
        let bump = b > 0 && b < 1 ? sin(b * .pi) : 0
        return Text("\(n)")
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.92))
            .contentTransition(.numericText(value: Double(n)))
            .animation(.snappy(duration: 0.25), value: n)
            .scaleEffect(1 + 0.3 * bump)
    }

    private func paper(_ p: Double) -> some View {
        let e = p * p * (3 - 2 * p)
        let from = notchHeight / 2
        let to = notchHeight + Self.drawer / 2 - 1
        let y = from + (to - from) * e - 7 * sin(p * .pi)
        let x = countX + (countOnLeft ? 3 : -3) * sin(p * .pi)
        let fade = p < 0.15 ? p / 0.15 : (p > 0.85 ? max(0, (1 - p) / 0.15) : 1)
        return Paper(tint: tick.verdict.color)
            .frame(width: 10, height: 13)
            .scaleEffect(0.75 + 0.35 * sin(p * .pi) - 0.25 * max(0, p - 0.8) / 0.2)
            .rotationEffect(.degrees(-18 + 26 * e))
            .opacity(fade)
            .position(x: x, y: y)
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
