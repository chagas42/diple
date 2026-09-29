import SwiftUI

struct PixelArt: View {
    let artifact: Artifact

    var body: some View {
        Canvas { ctx, size in
            let rows = artifact.pixels
            let n = CGFloat(rows.count)
            let cell = min(size.width, size.height) / n
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let hex = artifact.palette[ch] else { continue }
                    let r = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.3, height: cell + 0.3)
                    ctx.fill(Path(r), with: .color(Color(hex: hex)))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct ArtifactTile: View {
    let artifact: Artifact
    var side: CGFloat = 104
    var start = Date()

    private var tint: Color { artifact.rarity.color }
    private var inset: CGFloat { side * 0.14 }
    private var corner: CGFloat { side * 0.14 }

    var body: some View {
        TimelineView(.animation(paused: !artifact.rarity.shimmers)) { context in
            let t = context.date.timeIntervalSince(start)
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.08)],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(tint.opacity(0.7), lineWidth: artifact.rarity >= .rare ? 1.5 : 1)
                if artifact.rarity.sparks { Sparks(t: t, tint: tint, reach: side * 0.45) }
                PixelArt(artifact: artifact)
                    .padding(inset)
                    .shadow(color: tint.opacity(artifact.rarity >= .uncommon ? 0.6 : 0), radius: side * 0.08)
                if artifact.rarity.shimmers { holo(t) }
                if artifact.rarity.shines { shine(t) }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    private func holo(_ t: Double) -> some View {
        AngularGradient(
            colors: [.pink, .yellow, .green, .cyan, .blue, .purple, .pink],
            center: .center, angle: .degrees(t * 70)
        )
        .opacity(0.28)
        .blendMode(.overlay)
        .mask(PixelArt(artifact: artifact).padding(inset))
    }

    private func shine(_ t: Double) -> some View {
        let p = (t.truncatingRemainder(dividingBy: 1.8)) / 1.8
        return LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                              startPoint: .leading, endPoint: .trailing)
            .frame(width: side * 0.33)
            .rotationEffect(.degrees(20))
            .offset(x: side * (-0.9 + 1.8 * p))
            .blendMode(.plusLighter)
    }
}

struct ClaimCard: View {
    let reward: Reward
    let leaving: Bool
    @State private var shown = false
    @State private var start = Date()

    private var artifact: Artifact { reward.artifact }

    var body: some View {
        VStack(spacing: 12) {
            ArtifactTile(artifact: artifact, side: 168, start: start)
            Text(artifact.rarity.title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(artifact.rarity.color)
            Text(artifact.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(artifact.flavor)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let pr = reward.pr {
                Text("for reviewing \(pr)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("Click to keep it")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(artifact.rarity.color.opacity(0.45), lineWidth: 1)
                )
                .shadow(color: artifact.rarity.color.opacity(0.35), radius: 24)
        )
        .scaleEffect(leaving ? 0.12 : (shown ? 1 : 0.4))
        .rotation3DEffect(.degrees(shown ? 0 : 160), axis: (x: 0, y: 1, z: 0))
        .offset(y: leaving ? -320 : (shown ? 0 : -140))
        .opacity(leaving ? 0 : (shown ? 1 : 0))
        .onAppear {
            start = Date()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.66)) { shown = true }
        }
    }
}

struct Sparks: View {
    let t: Double
    let tint: Color
    var reach: CGFloat = 46
    var count = 18

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<count {
                let life = 1.4
                let p = ((t + Double(i) * 0.19).truncatingRemainder(dividingBy: life)) / life
                let a = Double(i) * 2.39996
                let d = reach * (0.2 + 0.8 * p)
                let pt = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
                let s = 3.2 * (1 - p)
                ctx.opacity = 1 - p
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - s / 2, y: pt.y - s / 2, width: s, height: s)),
                         with: .color(i.isMultiple(of: 3) ? .white : tint))
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
