import SwiftUI

struct LidView: View {
    let stickers: [(id: String, artifact: Artifact)]
    var justStuck: String?

    static let ratio: CGFloat = 1.52

    struct Placement: Equatable {
        let x: CGFloat
        let y: CGFloat
        let angle: Double
        let size: CGFloat
    }

    static func placement(for id: String) -> Placement {
        var seed = id.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(1 << 31)
        }
        var x = 0.1 + 0.8 * next(), y = 0.13 + 0.74 * next()
        if abs(x - 0.5) < 0.14, abs(y - 0.5) < 0.18 { x += x < 0.5 ? -0.2 : 0.2 }
        return Placement(x: x, y: y, angle: Double(next() * 36 - 18), size: 0.13 + 0.04 * next())
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.80), Color(white: 0.68)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(brushed.clipShape(RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)))
                    .overlay(
                        RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                Text("\u{203A}")
                    .font(.system(size: w * 0.07, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .shadow(color: .white.opacity(0.3), radius: 4)
                ForEach(stickers, id: \.id) { s in
                    let p = Self.placement(for: s.id)
                    Stuck(artifact: s.artifact, fresh: s.id == justStuck)
                        .frame(width: w * p.size, height: w * p.size)
                        .rotationEffect(.degrees(p.angle))
                        .position(x: w * p.x, y: h * p.y)
                }
            }
        }
        .aspectRatio(Self.ratio, contentMode: .fit)
    }

    private var brushed: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            var i = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)),
                         with: .color(.white.opacity(i.isMultiple(of: 3) ? 0.10 : 0.04)))
                y += 2.2
                i += 1
            }
        }
    }

    private struct Stuck: View {
        let artifact: Artifact
        let fresh: Bool
        @State private var landed = false

        var body: some View {
            StickerFace(artifact: artifact)
                .scaleEffect(landed ? 1 : 1.45)
                .rotationEffect(.degrees(landed ? 0 : -14))
                .offset(y: landed ? 0 : -18)
                .shadow(color: .black.opacity(landed ? 0 : 0.35), radius: landed ? 0 : 14, y: landed ? 0 : 12)
                .opacity(landed ? 1 : 0)
                .onAppear {
                    guard fresh else { landed = true; return }
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { landed = true }
                }
        }
    }
}
