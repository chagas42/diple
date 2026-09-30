import SwiftUI

struct SleepyZs: View {
    let start: Date
    var quick = false

    static let afterTheEye = 0.9
    static let quickAfterTheEye = 0.1

    static let size = CGSize(width: 200, height: 130)
    static let eye = CGPoint(x: 145, y: 8)

    private var afterTheEye: Double { quick ? Self.quickAfterTheEye : Self.afterTheEye }
    private var every: Double { quick ? 0.28 : 0.55 }
    private var life: Double { quick ? 1.3 : 2.6 }
    private static let lanes: [CGVector] = [
        CGVector(dx: -100, dy: 34), CGVector(dx: -52, dy: 84), CGVector(dx: 30, dy: 92),
    ]
    private static let letters: [(String, CGFloat)] = [("z", 12), ("z", 15), ("Z", 20)]

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start) - afterTheEye
            let newest = max(0, Int(elapsed / every))
            let oldest = max(0, newest - Int(life / every))
            ZStack {
                ForEach(oldest...max(oldest, newest), id: \.self) { i in
                    let p = (elapsed - Double(i) * every) / life
                    if p >= 0, p <= 1 { letter(i, p) }
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }
        .allowsHitTesting(false)
    }

    private func letter(_ i: Int, _ p: Double) -> some View {
        let lane = Self.lanes[i % Self.lanes.count]
        let (text, size) = Self.letters[(i / Self.lanes.count + i) % Self.letters.count]
        let sway = 6 * sin(p * .pi * 2 + Double(i))
        return Text(text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 1.5, y: 0.5)
            .scaleEffect(0.55 + 0.6 * p)
            .opacity(p < 0.15 ? p / 0.15 : 1 - (p - 0.15) / 0.85)
            .position(x: Self.eye.x + 6 + lane.dx * p + sway,
                      y: Self.eye.y + 8 + lane.dy * p)
    }
}
