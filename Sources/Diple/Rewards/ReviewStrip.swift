import SwiftUI

struct ReviewStrip: View {
    let tick: ReviewTick
    let start: Date

    static let drawer: CGFloat = 18

    static func length(_ t: ReviewTick) -> Double { t.reward == nil ? 1.5 : 2.3 }

    static func shortPR(_ key: String) -> String {
        let parts = key.split(separator: "/")
        return parts.count > 1 ? String(parts[1]) : key
    }

    static func label(_ t: ReviewTick) -> String {
        guard let leg = t.leg else { return "\(t.count) this season" }
        return "\(t.count)/\(leg.to)"
    }

    static func fill(_ t: ReviewTick, _ p: Double) -> Double {
        guard let leg = t.leg else { return 1 }
        let span = Double(leg.to - leg.from)
        let before = Double(t.count - 1 - leg.from) / span
        let after = Double(t.count - leg.from) / span
        return max(0, before) + (after - max(0, before)) * p
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            let total = Self.length(tick)
            let inOut = min(1, t / 0.18) * (1 - max(0, (t - (total - 0.25)) / 0.25))
            let step = Self.ease(min(1, max(0, (t - 0.2) / 0.5)))
            HStack(spacing: 6) {
                Text("\u{203A}")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(tick.verdict.color)
                Text(tick.verdict.short)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tick.verdict.color)
                Text(Self.shortPR(tick.pr))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                bar(Self.ease(Self.fill(tick, step)))
                if let r = tick.reward {
                    PixelArt(artifact: r.artifact)
                        .frame(width: 13, height: 13)
                        .shadow(color: r.artifact.rarity.color, radius: 3)
                        .scaleEffect(t > 0.7 ? 1 : 0.2)
                        .opacity(t > 0.7 ? 1 : 0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: t > 0.7)
                } else {
                    Text(Self.label(tick))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(inOut)
        }
        .allowsHitTesting(false)
    }

    private func bar(_ p: Double) -> some View {
        let tint = tick.reward?.artifact.rarity.color ?? tick.verdict.color
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.1))
            Capsule().fill(tint).frame(width: max(2, 64 * p))
        }
        .frame(width: 64, height: 3)
    }

    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
