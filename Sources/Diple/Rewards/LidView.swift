import SwiftUI

struct LidSpot: Codable, Sendable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var angle: Double
    var size: CGFloat
}

struct LidView: View {
    struct Item {
        let id: String
        let artifact: Artifact
        let spot: LidSpot?
    }

    let items: [Item]
    let onStick: (String, LidSpot) -> Void

    static let ratio: CGFloat = 1.52

    @State private var moved: [String: LidSpot] = [:]
    @State private var justStuck: String?

    static func placement(for id: String) -> LidSpot {
        var seed = id.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(1 << 31)
        }
        var x = 0.1 + 0.8 * next(), y = 0.13 + 0.74 * next()
        if abs(x - 0.5) < 0.14, abs(y - 0.5) < 0.18 { x += x < 0.5 ? -0.2 : 0.2 }
        return LidSpot(x: x, y: y, angle: Double(next() * 36 - 18), size: 0.13 + 0.04 * next())
    }

    static func clamped(_ s: LidSpot) -> LidSpot {
        var s = s
        s.x = min(0.95, max(0.05, s.x))
        s.y = min(0.93, max(0.07, s.y))
        return s
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                shell(w)
                logo(w)
                ForEach(items.filter { $0.spot != nil }, id: \.id) { item in
                    let p = item.spot!
                    Stuck(artifact: item.artifact, fresh: item.id == justStuck)
                        .frame(width: w * p.size, height: w * p.size)
                        .rotationEffect(.degrees(p.angle))
                        .position(x: w * p.x, y: h * p.y)
                }
                ForEach(items.filter { $0.spot == nil }, id: \.id) { item in
                    let p = moved[item.id] ?? Self.placement(for: item.id)
                    Lifted(artifact: item.artifact, width: w * p.size, angle: p.angle) {
                        justStuck = item.id
                        onStick(item.id, p)
                        moved[item.id] = nil
                    }
                    .position(x: w * p.x, y: h * p.y + 12)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("lid"))
                            .onChanged { v in
                                var q = p
                                q.x = v.location.x / w
                                q.y = v.location.y / h
                                moved[item.id] = Self.clamped(q)
                            }
                    )
                }
            }
            .coordinateSpace(name: "lid")
        }
        .aspectRatio(Self.ratio, contentMode: .fit)
    }

    private func shell(_ w: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.43, green: 0.44, blue: 0.47), Color(red: 0.31, green: 0.32, blue: 0.35)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(brushed.clipShape(RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)))
            .overlay(
                RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }

    private func logo(_ w: CGFloat) -> some View {
        ZStack {
            RadialGradient(colors: [.white.opacity(0.28), .white.opacity(0)], center: .center,
                           startRadius: 0, endRadius: w * 0.09)
                .frame(width: w * 0.2, height: w * 0.2)
            Text("\u{203A}")
                .font(.system(size: w * 0.075, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .white, radius: w * 0.012)
                .shadow(color: .white.opacity(0.6), radius: w * 0.03)
        }
    }

    private var brushed: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            var i = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)),
                         with: .color(.white.opacity(i.isMultiple(of: 3) ? 0.06 : 0.025)))
                y += 2.2
                i += 1
            }
        }
    }

    private struct Lifted: View {
        let artifact: Artifact
        let width: CGFloat
        let angle: Double
        let stick: () -> Void
        @State private var bob = false

        var body: some View {
            VStack(spacing: 6) {
                StickerFace(artifact: artifact)
                    .frame(width: width, height: width)
                    .scaleEffect(1.12)
                    .rotationEffect(.degrees(angle))
                    .offset(y: bob ? -3 : 0)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 14)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
                    }
                Button(action: stick) {
                    Label("Stick it", systemImage: "hand.point.down.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
            .contentShape(Rectangle())
            .help("Drag it where you want it, then stick it. Once stuck, it stays.")
        }
    }

    private struct Stuck: View {
        let artifact: Artifact
        let fresh: Bool
        @State private var landed = false

        var body: some View {
            StickerFace(artifact: artifact)
                .scaleEffect(landed ? 1 : 1.12)
                .offset(y: landed ? 0 : -3)
                .shadow(color: .black.opacity(landed ? 0 : 0.35), radius: landed ? 0 : 12, y: landed ? 0 : 14)
                .onAppear {
                    guard fresh else { landed = true; return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { landed = true }
                }
        }
    }
}
