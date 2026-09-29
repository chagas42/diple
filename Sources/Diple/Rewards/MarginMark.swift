import SwiftUI

struct MarginMark: View {
    let reward: Reward
    let start: Date

    static let length = 2.8
    static let drawer: CGFloat = 28

    private static let ink = Color(red: 0.79, green: 0.64, blue: 0.42)
    private static let quill = Artifact(
        id: "quill", name: "Quill", flavor: "", rarity: .common,
        pixels: [
            "..........WW",
            ".........WWW",
            "........WWWG",
            ".......WWWG.",
            "......WWWG..",
            ".....WWWG...",
            "....WWWG....",
            "...WWWG.....",
            "...WWG......",
            "..WG........",
            ".T..........",
            "T...........",
        ],
        palette: ["W": 0xF2EBDD, "G": 0x9C927F, "T": 0xC9A46A]
    )

    private static let appear = (from: 0.2, to: 0.35)
    private static let mark = (from: 0.35, to: 0.8)
    private static let turn = (from: 0.8, to: 1.0)
    private static let type = (from: 1.0, to: 1.75)
    private static let tally = (from: 1.7, to: 1.9)
    private static let leave = (from: 2.35, to: 2.6)
    private static let progress = (from: 0.35, to: 1.75)

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            let m = Self.ease(Self.phase(t, Self.mark))
            let turned = Self.phase(t, Self.turn)
            let typed = Self.phase(t, Self.type)
            let word = reward.verdict.word
            let shown = String(word.prefix(Int((Double(word.count) * typed).rounded(.down))))
            let cursor = t > Self.turn.from && (typed < 1 || Int(t * 3).isMultiple(of: 2))

            HStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    Diple()
                        .trim(from: 0, to: m)
                        .stroke(turned > 0 ? reward.verdict.color : Self.ink,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 7, height: 11)
                        .shadow(color: reward.verdict.color.opacity(0.7 * turned), radius: 3)
                    PixelArt(artifact: Self.quill)
                        .frame(width: 13, height: 13)
                        .offset(x: Self.tipX(m), y: 11 * m - 11.5)
                        .opacity(1 - turned)
                }
                .frame(width: 20, alignment: .leading)

                HStack(spacing: 1) {
                    Text(shown)
                        .foregroundStyle(reward.verdict.color)
                    Rectangle()
                        .fill(reward.verdict.color)
                        .frame(width: 6, height: 11)
                        .opacity(cursor ? 0.9 : 0)
                }
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))

                Spacer(minLength: 4)

                Text(Self.tally(reward))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(reward.artifact.rarity.color)
                    .opacity(Self.phase(t, Self.tally))
                    .offset(y: 4 * (1 - Self.ease(Self.phase(t, Self.tally))))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) { bar(Self.fill(reward, Self.ease(Self.phase(t, Self.progress)))) }
            .opacity(Self.phase(t, Self.appear) * (1 - Self.phase(t, Self.leave)))
        }
        .allowsHitTesting(false)
    }

    static func tally(_ r: Reward) -> String {
        guard let goal = r.goal, goal > 0 else { return "+1 · \(r.today) today" }
        return r.today == goal ? "+1 · daily goal \u{2713}" : "+1 · \(r.today)/\(goal) today"
    }

    static func fill(_ r: Reward, _ p: Double) -> Double {
        guard let goal = r.goal, goal > 0 else { return p }
        let from = min(1, Double(r.today - 1) / Double(goal))
        let to = min(1, Double(r.today) / Double(goal))
        return from + (to - from) * p
    }

    private func bar(_ p: Double) -> some View {
        GeometryReader { geo in
            let full = geo.size.width - 32
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [reward.verdict.color.opacity(0.35), reward.verdict.color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, full * p))
                    .shadow(color: reward.verdict.color.opacity(p < 1 ? 0.9 : 0.4), radius: 3)
            }
            .frame(width: full, height: 2)
            .offset(x: 16, y: geo.size.height - 5)
        }
    }

    private struct Diple: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            return p
        }
    }

    private static func tipX(_ m: Double) -> Double { 7 * (m < 0.5 ? 2 * m : 2 - 2 * m) }

    private static func phase(_ t: Double, _ span: (from: Double, to: Double)) -> Double {
        min(1, max(0, (t - span.from) / (span.to - span.from)))
    }

    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
