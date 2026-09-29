import SwiftUI
import CoreText

struct SignatureCelebration: View {
    let rarity: Rarity
    let today: Int
    let start: Date

    static let length = 2.6
    static var size: CGSize { CGSize(width: signature.size.width + 60, height: 58) }

    private static let write = (from: 0.15, to: 1.15)
    private static let tick = (from: 1.15, to: 1.45)
    private static let away = (from: 2.05, to: 2.6)

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            let w = Self.ease(Self.phase(t, Self.write))
            let k = Self.ease(Self.phase(t, Self.tick))
            let a = Self.ease(Self.phase(t, Self.away))
            let sig = Self.signature
            ZStack(alignment: .topLeading) {
                sig.path
                    .fill(.white)
                    .shadow(color: .black.opacity(0.7), radius: 1.5, y: 0.5)
                    .shadow(color: rarity.color.opacity(0.6 * k), radius: 6)
                    .mask(alignment: .leading) {
                        LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: sig.size.width * w + 8)
                    }
                    .frame(width: sig.size.width, height: sig.size.height, alignment: .topLeading)
                    .offset(x: 12, y: 6)

                if w > 0, w < 1 {
                    Image(systemName: "pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 1.5)
                        .offset(x: 12 + sig.size.width * w - 3, y: -4 + 4 * sin(w * .pi * 9))
                }

                Check()
                    .trim(from: 0, to: k)
                    .stroke(rarity.color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .shadow(color: rarity.color, radius: 4)
                    .frame(width: 18, height: 14)
                    .offset(x: 20 + sig.size.width, y: 12)

                if k > 0 {
                    Sparks(t: t - Self.tick.from, tint: rarity.color, reach: 18, count: rarity >= .rare ? 12 : 7)
                        .frame(width: 40, height: 40)
                        .offset(x: 9 + sig.size.width, y: 0)
                        .opacity(1 - Self.phase(t, (Self.tick.from, Self.away.from)))
                }

                Text("+1 · \(today) today")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(rarity.color.opacity(0.85), in: Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .scaleEffect(0.7 + 0.3 * Self.ease(Self.phase(t, (1.45, 1.7))))
                    .opacity(Self.phase(t, (1.45, 1.6)))
                    .offset(x: Self.size.width / 2 - 34, y: 38)
            }
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .scaleEffect(1 - 0.5 * a, anchor: .top)
            .offset(y: -22 * a)
            .opacity(1 - a)
        }
        .allowsHitTesting(false)
    }

    private static func phase(_ t: Double, _ span: (from: Double, to: Double)) -> Double {
        min(1, max(0, (t - span.from) / (span.to - span.from)))
    }

    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    private struct Check: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            return p
        }
    }

    static let signature: (path: Path, size: CGSize) = {
        let font = CTFontCreateWithName("SnellRoundhand-Bold" as CFString, 26, nil)
        let text = NSAttributedString(string: "Reviewed", attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(text)
        let ascent = CTFontGetAscent(font)
        let out = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var points = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &points)
            for (g, p) in zip(glyphs, points) {
                let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: p.x, ty: ascent - p.y)
                if let glyph = CTFontCreatePathForGlyph(font, g, nil) { out.addPath(glyph, transform: flip) }
            }
        }
        let box = out.boundingBoxOfPath
        let shifted = Path(out).offsetBy(dx: -box.minX, dy: -box.minY)
        return (shifted, box.size)
    }()
}
