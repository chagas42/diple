import SwiftUI

struct EyeShape: Shape {
    var openness: CGFloat = 1

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in r: CGRect) -> Path {
        let cy = r.midY
        let h = (r.height / 2) * max(0.04, openness)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: cy))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: cy),
                       control: CGPoint(x: r.midX, y: cy - h * 2))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: cy),
                       control: CGPoint(x: r.midX, y: cy + h * 2))
        p.closeSubpath()
        return p
    }
}

@MainActor
final class EyeState: ObservableObject {
    @Published private(set) var gaze: CGPoint = .zero
    @Published var blinking = false
    @Published var lid: CGFloat = 1
    @Published var focused = false
    @Published var sore = false
    @Published var pokes = 0
    var lidSpeed: Double = 0.4

    func look(at next: CGPoint) {
        guard abs(next.x - gaze.x) > 0.01 || abs(next.y - gaze.y) > 0.01 else { return }
        gaze = next
    }
}

struct EyeView: View {
    @ObservedObject var eye: EyeState
    var width: CGFloat = 15

    private var gaze: CGPoint { eye.gaze }
    static let focusedLid: CGFloat = 0.42
    static let focusedWhite = Color(red: 0.80, green: 0.78, blue: 1)
    static let soreWhite = Color(red: 1, green: 0.70, blue: 0.72)

    private var white: Color {
        eye.sore ? Self.soreWhite : eye.focused ? Self.focusedWhite : .white.opacity(0.94)
    }

    private var openness: CGFloat {
        eye.blinking ? 0.05 : max(0.14, eye.focused ? min(eye.lid, Self.focusedLid) : eye.lid)
    }
    private var shape: EyeShape { EyeShape(openness: openness) }
    private var pupil: CGFloat { width * 0.30 }
    private var range: CGFloat { width * 0.17 }

    var body: some View {
        let _ = Metrics.shared.body("EyeView")
        ZStack {
            shape.fill(white)
            Circle()
                .fill(Color(red: 0.07, green: 0.08, blue: 0.10))
                .frame(width: pupil, height: pupil)
                .offset(x: gaze.x * range, y: gaze.y * range * 0.55)
                .overlay(
                    Circle()
                        .fill(.white.opacity(0.8))
                        .frame(width: pupil * 0.34, height: pupil * 0.34)
                        .offset(x: gaze.x * range - pupil * 0.22,
                                y: gaze.y * range * 0.55 - pupil * 0.22)
                )
        }
        .frame(width: width, height: width * 0.62)
        .clipShape(shape)
        .animation(.easeInOut(duration: 0.085), value: eye.blinking)
        .animation(.easeInOut(duration: eye.lidSpeed), value: eye.lid)
        .animation(.easeInOut(duration: 0.35), value: eye.focused)
        .animation(.easeOut(duration: 0.12), value: eye.sore)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: eye.pokes) { view, dx in
            view.offset(x: dx)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-2.5, duration: 0.05)
                CubicKeyframe(2.5, duration: 0.07)
                CubicKeyframe(-2, duration: 0.07)
                CubicKeyframe(1.5, duration: 0.07)
                CubicKeyframe(-1, duration: 0.07)
                CubicKeyframe(0, duration: 0.08)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.6), value: gaze)
    }
}
