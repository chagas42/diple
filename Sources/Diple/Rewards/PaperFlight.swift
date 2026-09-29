import SwiftUI

enum PaperStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case filed, dropped
    var id: String { rawValue }
    var title: String {
        switch self {
        case .filed:   "Filed into the notch"
        case .dropped: "Dropped off the pile"
        }
    }
}

struct PaperFlight: View {
    let style: PaperStyle
    let tint: Color
    let start: Date

    static let length = 0.9

    var body: some View {
        TimelineView(.animation) { context in
            let p = min(1, context.date.timeIntervalSince(start) / Self.length)
            let pose = style == .filed ? Self.filed(p) : Self.dropped(p)
            Sheet(tint: tint)
                .frame(width: 13, height: 17)
                .scaleEffect(pose.scale)
                .rotationEffect(.degrees(pose.angle))
                .offset(x: pose.x, y: pose.y)
                .opacity(pose.opacity)
        }
        .allowsHitTesting(false)
    }

    struct Pose { var x: CGFloat; var y: CGFloat; var angle: Double; var scale: CGFloat; var opacity: Double }

    static func filed(_ p: Double) -> Pose {
        let e = 1 - pow(1 - p, 2.2)
        return Pose(x: CGFloat(70 * (1 - e)), y: CGFloat(120 * (1 - e) - 40 * sin(e * .pi)),
                    angle: 40 * (1 - e) - 8, scale: CGFloat(1.2 - 0.7 * e),
                    opacity: p < 0.12 ? p / 0.12 : (p > 0.85 ? (1 - p) / 0.15 : 1))
    }

    static func dropped(_ p: Double) -> Pose {
        let e = p * p
        return Pose(x: CGFloat(10 * sin(p * .pi * 2.4)), y: CGFloat(4 + 190 * e),
                    angle: 18 * sin(p * .pi * 2.2), scale: CGFloat(0.7 + 0.5 * min(1, p * 3)),
                    opacity: p < 0.1 ? p / 0.1 : 1 - max(0, p - 0.55) / 0.45)
    }

    private struct Sheet: View {
        let tint: Color
        var body: some View {
            ZStack(alignment: .topLeading) {
                Folded().fill(Color(white: 0.96))
                Folded().stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                VStack(alignment: .leading, spacing: 2.2) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(i == 0 ? tint : Color.black.opacity(0.22))
                            .frame(width: i == 3 ? 5 : 8, height: 1.3)
                    }
                }
                .padding(.leading, 2.5)
                .padding(.top, 5)
            }
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
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
