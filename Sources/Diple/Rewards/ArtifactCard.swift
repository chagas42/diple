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
    private var corner: CGFloat { side * 0.14 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.05)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            StickerFace(artifact: artifact, start: start)
                .padding(side * 0.1)
                .rotationEffect(.degrees(Self.tilt(artifact)))
        }
        .frame(width: side, height: side)
    }

    static func tilt(_ a: Artifact) -> Double {
        Double(a.id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 7 - 3) * 1.2
    }
}

struct StickerFace: View {
    let artifact: Artifact
    var start = Date()

    private static var cache: [String: NSImage] = [:]

    static func image(_ a: Artifact) -> NSImage {
        if let hit = cache[a.id] { return hit }
        let img = StickerShape.image(a)
        cache[a.id] = img
        return img
    }

    var body: some View {
        let img = Self.image(artifact)
        let face = Image(nsImage: img).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !artifact.rarity.shimmers)) { context in
            let t = context.date.timeIntervalSince(start)
            face
                .overlay {
                    if artifact.rarity.shimmers {
                        LinearGradient(
                            colors: [.pink, .yellow, .mint, .cyan, .purple, .pink],
                            startPoint: UnitPoint(x: 0.5 + 0.5 * cos(t * 0.6), y: 0),
                            endPoint: UnitPoint(x: 0.5 - 0.5 * cos(t * 0.6), y: 1)
                        )
                        .opacity(artifact.rarity == .legendary ? 0.22 : 0.16)
                        .blendMode(.overlay)
                        .mask(face)
                    }
                }
                .overlay {
                    LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.06)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .blendMode(.softLight)
                        .mask(face)
                }
                .shadow(color: .black.opacity(0.28), radius: 1.2, x: 0, y: 1)
                .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 3)
        }
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
            Text("Click to put it in your backpack")
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
        .scaleEffect(shown ? 1 : 0.4)
        .rotation3DEffect(.degrees(shown ? 0 : 160), axis: (x: 0, y: 1, z: 0))
        .offset(y: shown ? 0 : -140)
        .opacity(shown ? 1 : 0)
        .onAppear {
            start = Date()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.66)) { shown = true }
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
