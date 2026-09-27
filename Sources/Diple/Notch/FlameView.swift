import SwiftUI

struct FlameView: View {
    var size: CGFloat = 20

    @State private var flicker: CGFloat = 0
    @State private var sway: CGFloat = 0
    @State private var sparkPhase: CGFloat = 0

    private let ember = Color(red: 0.72, green: 0.13, blue: 0.03)
    private let blaze = Color(red: 1.00, green: 0.45, blue: 0.05)
    private let core  = Color(red: 1.00, green: 0.86, blue: 0.38)

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [blaze.opacity(0.55), blaze.opacity(0)],
                        center: .center, startRadius: 0, endRadius: size * 0.85
                    )
                )
                .frame(width: size * 1.9, height: size * 1.9)
                .opacity(0.65 + flicker * 0.35)

            ForEach(0..<3, id: \.self) { i in
                let t = (sparkPhase + CGFloat(i) * 0.33).truncatingRemainder(dividingBy: 1)
                Circle()
                    .fill(core)
                    .frame(width: 2 - CGFloat(i) * 0.4, height: 2 - CGFloat(i) * 0.4)
                    .offset(
                        x: sin((t + CGFloat(i)) * 6) * size * 0.22,
                        y: -size * 0.45 - t * size * 0.75
                    )
                    .opacity((1 - t) * 0.9)
            }

            FlameShape()
                .fill(
                    LinearGradient(
                        colors: [ember, blaze, core],
                        startPoint: .bottom, endPoint: .top
                    )
                )
                .frame(width: size * 0.72, height: size)
                .scaleEffect(x: 1 - flicker * 0.06, y: 0.9 + flicker * 0.18, anchor: .bottom)
                .rotationEffect(.degrees(sway * 5), anchor: .bottom)

            FlameShape()
                .fill(core)
                .frame(width: size * 0.3, height: size * 0.44)
                .offset(y: size * 0.2)
                .scaleEffect(y: 0.85 + flicker * 0.3, anchor: .bottom)
                .opacity(0.75 + flicker * 0.25)
                .blur(radius: 0.4)
        }
        .frame(width: size * 1.9, height: size * 1.9)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.17).repeatForever(autoreverses: true)) {
                flicker = 1
            }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                sway = 1
            }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                sparkPhase = 1
            }
        }
    }
}

struct FlameShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addCurve(
            to: CGPoint(x: w, y: h * 0.62),
            control1: CGPoint(x: w * 0.72, y: h * 0.2),
            control2: CGPoint(x: w * 0.98, y: h * 0.36)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w, y: h * 0.86),
            control2: CGPoint(x: w * 0.78, y: h)
        )
        p.addCurve(
            to: CGPoint(x: 0, y: h * 0.62),
            control1: CGPoint(x: w * 0.22, y: h),
            control2: CGPoint(x: 0, y: h * 0.86)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.46, y: h * 0.26),
            control1: CGPoint(x: 0, y: h * 0.34),
            control2: CGPoint(x: w * 0.34, y: h * 0.42)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w * 0.54, y: h * 0.14),
            control2: CGPoint(x: w * 0.5, y: h * 0.07)
        )
        p.closeSubpath()
        return p
    }
}
