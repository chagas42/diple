import SwiftUI
import AppKit

enum Onboarding {
    static let version = 1

    static func steps(managesRotation: Bool, start: Step = .welcome) -> [Step] {
        Step.allCases.filter { $0 != .reviews || managesRotation || start == .reviews }
    }

    enum Step: Int, CaseIterable {
        case welcome, github, team, reviews, notch, hours, ranking, extras, tryIt, done
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var start: Onboarding.Step = .welcome
    var celebrates = false
    let finish: () -> Void

    @State private var step: Onboarding.Step = .welcome
    @State private var forward = true
    @State private var previewFocused = false
    @State private var celebration: Date?
    @StateObject private var eye = EyeState()
    @StateObject private var rotation = RotationPreview()

    var body: some View {
        VStack(spacing: 0) {
            NotchStage(model: model, step: step, eye: eye, focused: previewFocused, rotation: rotation) { Task { await poke() } }
                .frame(height: 236)
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .top) {
                    content
                        .frame(maxWidth: 500)
                        .frame(maxWidth: .infinity)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 48)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .overlay { if let celebration { ReviewBurst(start: celebration) } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .onAppear { step = start }
        .task(id: model.org) { await model.refreshRotationAccess() }
    }

    private var steps: [Onboarding.Step] { Onboarding.steps(managesRotation: model.managesRotation, start: start) }

    private func neighbor(_ offset: Int) -> Onboarding.Step? {
        guard let i = steps.firstIndex(of: step), steps.indices.contains(i + offset) else { return nil }
        return steps[i + offset]
    }

    private func go(_ next: Onboarding.Step) {
        forward = next.rawValue > step.rawValue
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { step = next }
    }

    private var footer: some View {
        HStack {
            if step != .done {
                Button("Skip") { finish() }.buttonStyle(.link)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(steps, id: \.rawValue) { s in
                    Capsule()
                        .fill(s == step ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            Spacer()
            if let back = neighbor(-1), step != .done {
                Button("Back") { go(back) }
            }
            if step == .done {
                LaunchButton(title: "Start using Diple", presses: celebrates) {
                    celebration = Date()
                    Task {
                        try? await Task.sleep(for: .milliseconds(3700))
                        finish()
                    }
                }
            } else if let next = neighbor(1) {
                Button(step == .welcome ? "Get Started" : "Continue") { go(next) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: WelcomeStep()
        case .github: GitHubStep(model: model)
        case .team: TeamStep(model: model)
        case .reviews: ReviewsStep(model: model, preview: rotation)
        case .notch: NotchStep(model: model)
        case .hours: HoursStep(model: model)
        case .ranking: RankingStep(model: model)
        case .extras: ExtrasStep(model: model)
        case .tryIt: TryItStep(focused: previewFocused)
        case .done: DoneStep(model: model)
        }
    }

    private func poke() async {
        guard !eye.sore else { return }
        eye.pokes += 1
        eye.complaining = true
        eye.sore = true
        eye.lidSpeed = 0.05
        eye.lid = 0.1
        try? await Task.sleep(for: .milliseconds(480))
        withAnimation(.easeInOut(duration: 0.35)) { previewFocused.toggle() }
        eye.focused = previewFocused
        eye.lidSpeed = 0.3
        eye.lid = 1
        eye.sore = false
        try? await Task.sleep(for: .milliseconds(450))
        eye.complaining = false
        eye.lidSpeed = 0.4
    }
}

struct StepHeader: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }
}

struct NotchStage: View {
    @ObservedObject var model: AppModel
    let step: Onboarding.Step
    @ObservedObject var eye: EyeState
    let focused: Bool
    @ObservedObject var rotation: RotationPreview
    let onPoke: () -> Void

    @State private var awake = false
    @State private var glow = false
    @State private var cursor = CGPoint(x: 560, y: 170)
    @State private var showsCursor = true
    @State private var pressing = false
    @State private var picked = 1
    @State private var typed = 0
    @State private var lit = 0
    @State private var bars: [CGFloat] = [0.5, 0.8, 0.4, 0.7]
    @State private var popped = 0
    @State private var count = 3
    @State private var ring = false

    static let eyeAt = CGPoint(x: 240, y: 19)
    static let rightEyeAt = CGPoint(x: 480, y: 19)
    static let command = "gh auth status"
    static let avatars: [CGFloat] = [284, 322, 360, 398, 436]

    private var settings: Settings { model.settings }
    private var showsEye: Bool { settings.showsEye || step == .tryIt }
    private var eyeOnRight: Bool { settings.countSide == .left && step != .tryIt }
    private var eyeCenter: CGPoint { eyeOnRight ? Self.rightEyeAt : Self.eyeAt }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.10, green: 0.09, blue: 0.16), Color(red: 0.05, green: 0.05, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.accentColor.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 320)
                .opacity(glow ? 1 : 0.5)
            VStack(spacing: 18) {
                notch
                below.id(step).transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .frame(maxWidth: .infinity)
            if showsCursor, step != .done {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .scaleEffect(pressing ? 0.82 : 1, anchor: .topLeading)
                    .position(x: cursor.x + 6, y: cursor.y + 9)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(width: 720)
        .clipped()
        .task(id: step) { await script() }
        .onAppear {
            eye.lid = 0.05
            Task {
                try? await Task.sleep(for: .milliseconds(1200))
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                eye.lidSpeed = 0.5
                eye.lid = 1
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { awake = true }
                try? await Task.sleep(for: .milliseconds(900))
                eye.blinking = true
                try? await Task.sleep(for: .milliseconds(120))
                eye.blinking = false
            }
        }
    }

    private func gaze(_ p: CGPoint) -> CGPoint {
        CGPoint(x: max(-1, min(1, (p.x - eyeCenter.x) / 240)), y: max(-1, min(1, (p.y - eyeCenter.y) / 120)))
    }

    private func move(_ p: CGPoint, _ seconds: Double = 0.9) async {
        withAnimation(.easeInOut(duration: seconds)) { cursor = p }
        eye.look(at: gaze(p))
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func click() async {
        withAnimation(.easeOut(duration: 0.08)) { pressing = true }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeOut(duration: 0.12)) { pressing = false }
    }

    private func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func script() async {
        withAnimation { showsCursor = ![.done, .github, .hours, .reviews].contains(step) }
        while !Task.isCancelled {
            switch step {
            case .welcome:
                for p in [CGPoint(x: 150, y: 140), CGPoint(x: 560, y: 90), CGPoint(x: 430, y: 190), CGPoint(x: 250, y: 70)] {
                    guard !Task.isCancelled else { return }
                    await move(p, 1.1)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { count = count >= 9 ? 3 : count + 1 }
                    await pause(0.35)
                }
            case .github:
                for i in 0...Self.command.count {
                    guard !Task.isCancelled else { return }
                    typed = i
                    await pause(0.06)
                }
                await pause(0.35)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { typed = Self.command.count + 1 }
                await pause(2.2)
                typed = 0
            case .team:
                for k in [3, 0, 2] {
                    guard !Task.isCancelled else { return }
                    await move(CGPoint(x: Self.avatars[k], y: 71), 0.9)
                    await click()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { picked = k }
                    await pause(0.9)
                }
            case .reviews:
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { picked = (picked + 1) % Self.avatars.count }
                await pause(1.1)
            case .notch:
                for p in [CGPoint(x: 200, y: 90), CGPoint(x: 520, y: 60), CGPoint(x: 360, y: 180)] {
                    guard !Task.isCancelled else { return }
                    await move(p, 1.2)
                    await pause(0.4)
                }
            case .hours:
                for i in 0...7 where lit < 7 {
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { lit = i }
                    await pause(0.09)
                }
                await pause(3600)
            case .ranking:
                await move(CGPoint(x: 470, y: 130), 0.8)
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                    bars = (0..<4).map { _ in CGFloat.random(in: 0.25...1) }
                }
                await pause(1.2)
            case .extras:
                for i in 0...3 {
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { popped = i }
                    await pause(0.35)
                }
                await pause(1.8)
                withAnimation(.easeOut(duration: 0.25)) { popped = 0 }
                await pause(0.4)
            case .tryIt:
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { ring = true }
                if focused {
                    await move(CGPoint(x: 520, y: 150), 1)
                    await pause(2)
                } else {
                    await move(CGPoint(x: Self.eyeAt.x + 4, y: Self.eyeAt.y + 6), 1)
                    await pause(1.2)
                    await move(CGPoint(x: Self.eyeAt.x + 70, y: 90), 0.8)
                    await pause(0.4)
                }
            case .done:
                await pause(5)
            }
        }
    }

    private var notch: some View {
        let side = settings.countSide
        return HStack(spacing: 0) {
            wing(showEye: showsEye && !eyeOnRight, showCount: side == .left && step != .tryIt)
            Spacer(minLength: 120)
            wing(showEye: showsEye && eyeOnRight, showCount: side == .right || step == .tryIt)
        }
        .frame(width: 300, height: 38)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14).fill(.black))
        .overlay(alignment: .bottom) {
            if focused {
                Capsule().fill(FocusCover.indigo.opacity(0.9)).frame(width: 40, height: 3).offset(y: -4).transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
        .scaleEffect(awake ? 1 : 0.85, anchor: .top)
        .opacity(awake ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: settings.countSide)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: settings.showsEye)
    }

    private func wing(showEye: Bool, showCount: Bool) -> some View {
        ZStack {
            if showEye {
                EyeView(eye: eye, width: 18)
                    .frame(width: 26, height: 26)
                    .overlay {
                        if step == .tryIt, !focused {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                                .frame(width: 34, height: 34)
                                .scaleEffect(ring ? 1.25 : 0.9)
                                .opacity(ring ? 0 : 0.9)
                        }
                    }
                    .overlay(alignment: .topLeading) { Complaint(eye: eye).fixedSize().offset(x: 16, y: 20) }
                    .contentShape(Rectangle().inset(by: -10))
                    .onTapGesture { if step == .tryIt { onPoke() } }
                    .transition(.scale.combined(with: .opacity))
            }
            if showCount {
                Text("\(max(count, model.count))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 60)
    }

    @ViewBuilder private var below: some View {
        switch step {
        case .welcome:
            Text("Your review queue, in the notch.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
        case .github:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("$ " + String(Self.command.prefix(typed)))
                    Rectangle().fill(.white.opacity(0.8)).frame(width: 7, height: 14).opacity(typed > Self.command.count ? 0 : 1)
                }
                if typed > Self.command.count {
                    Text("✓ Logged in to github.com").foregroundStyle(.green).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(width: 260, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
        case .team:
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    Circle().fill(Color(hue: Double(i) / 5, saturation: 0.35, brightness: 0.85))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(i == picked ? Color.accentColor : .black.opacity(0.5), lineWidth: i == picked ? 2.5 : 2))
                        .scaleEffect(i == picked ? 1.15 : 1)
                        .shadow(color: i == picked ? Color.accentColor.opacity(0.7) : .clear, radius: 6)
                }
            }
        case .reviews:
            RotationDiagram(people: rotation.people, rotation: rotation.rotation)
                .frame(width: 560)
                .environment(\.colorScheme, .dark)
        case .notch:
            DiffHunkView(hunk: AppearanceSettings.sample, path: "refund-policy.ts", folds: false)
                .environment(\.codeTheme, CodeTheme.named(settings.codeTheme))
                .frame(width: 440)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .scaleEffect(0.72, anchor: .top)
                .frame(height: 160, alignment: .top)
                .animation(.easeInOut(duration: 0.25), value: settings.codeTheme)
        case .hours:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(Array(DayPicker.order.enumerated()), id: \.offset) { i, d in
                        let on = settings.workDays.contains(d.0)
                        Text(String(d.1.prefix(1))).font(.system(size: 13, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(on ? Color.accentColor : .white.opacity(0.10)))
                            .overlay(Circle().strokeBorder(.white.opacity(on ? 0.0 : 0.18), lineWidth: 1))
                            .foregroundStyle(.white.opacity(on ? 1 : 0.6))
                            .scaleEffect(i < lit ? 1 : 0.6)
                            .opacity(i < lit ? 1 : 0)
                            .contentShape(Circle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                                    if on { model.settings.workDays.remove(d.0) } else { model.settings.workDays.insert(d.0) }
                                }
                            }
                            .help(d.1)
                    }
                }
                Text("Click a day").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            }
        case .ranking:
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(bars.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i == 2 ? AnyShapeStyle(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color.accentColor.opacity(0.75)))
                        .frame(width: 16, height: 50 * bars[i])
                }
            }
            .frame(height: 52, alignment: .bottom)
        case .extras:
            HStack(spacing: 14) {
                ForEach(Array(["power", "arrow.up.circle", "bell.badge"].enumerated()), id: \.offset) { i, icon in
                    Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white.opacity(0.85))
                        .scaleEffect(i < popped ? 1 : 0.3)
                        .opacity(i < popped ? 1 : 0)
                }
            }
            .frame(height: 30)
        case .tryIt:
            Text(focused ? "Focus is on. Alerts wait." : "Click the eye.")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                .contentTransition(.opacity)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34)).foregroundStyle(.green)
                .symbolEffect(.bounce, value: step)
        }
    }
}

struct LaunchButton: View {
    let title: String
    var presses = false
    let onDone: () -> Void

    @State private var progress: CGFloat = 0
    @State private var holding = false
    @State private var done = false
    @State private var shakes = 0
    @State private var pressure: CGFloat = 0
    @State private var ticks = 0
    @State private var hold: Task<Void, Never>?

    static let fillSeconds: CGFloat = 1.2
    static let tickAt: [CGFloat] = [0.25, 0.5, 0.75]

    var body: some View {
        label
            .overlay {
                PressSurface(
                    onDown: begin,
                    onUp: release,
                    onPressure: { stage, amount in
                        pressure = stage == 1 ? amount : 0
                        if stage >= 2 { finish() }
                    }
                )
            }
            .background {
                Button("", action: { begin(); Task { try? await Task.sleep(for: .seconds(Self.fillSeconds + 0.2)); release() } })
                    .keyboardShortcut(.defaultAction)
                    .opacity(0)
            }
            .task {
                guard presses else { return }
                try? await Task.sleep(for: .seconds(3))
                begin()
            }
            .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { view, dx in
                view.offset(x: dx)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-6, duration: 0.05)
                    CubicKeyframe(6, duration: 0.06)
                    CubicKeyframe(-5, duration: 0.06)
                    CubicKeyframe(4, duration: 0.06)
                    CubicKeyframe(-2, duration: 0.06)
                    CubicKeyframe(0, duration: 0.07)
                }
            }
            .scaleEffect(holding && !done ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: holding)
    }

    private func begin() {
        guard !done, hold == nil else { return }
        holding = true
        hold = Task { @MainActor in
            let step: CGFloat = 1.0 / 60
            while !Task.isCancelled, !done {
                progress = min(1, progress + step / Self.fillSeconds * (1 + 2 * pressure))
                if ticks < Self.tickAt.count, progress >= Self.tickAt[ticks] {
                    ticks += 1
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                if progress >= 1 { finish(); return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func release() {
        holding = false
        pressure = 0
        hold?.cancel()
        hold = nil
        guard !done else { return }
        ticks = 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { progress = 0 }
    }

    private func finish() {
        guard !done else { return }
        done = true
        hold?.cancel()
        hold = nil
        withAnimation(.easeOut(duration: 0.12)) { progress = 1 }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        shakes += 1
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            onDone()
        }
    }

    private var label: some View {
        Text(done ? "Here we go" : holding ? "Keep holding…" : title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.accentColor.opacity(holding || done ? 0.35 : 1))
                        Capsule().fill(Color.accentColor).frame(width: g.size.width * progress)
                    }
                }
            }
            .contentShape(Capsule())
            .help("Press and hold. Press harder for a deep click.")
    }
}

struct PressSurface: NSViewRepresentable {
    let onDown: () -> Void
    let onUp: () -> Void
    let onPressure: (Int, CGFloat) -> Void

    func makeNSView(context: Context) -> Surface {
        let v = Surface()
        v.pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDeepClick)
        return v
    }

    func updateNSView(_ v: Surface, context: Context) {
        v.onDown = onDown
        v.onUp = onUp
        v.onPressure = onPressure
    }

    final class Surface: NSView {
        var onDown: () -> Void = {}
        var onUp: () -> Void = {}
        var onPressure: (Int, CGFloat) -> Void = { _, _ in }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { onDown() }
        override func mouseUp(with event: NSEvent) { onUp() }
        override func pressureChange(with event: NSEvent) {
            onPressure(event.stage, CGFloat(event.pressure))
        }
    }
}

struct ReviewBurst: View {
    let start: Date

    enum Kind { case sheet, check, approved }

    struct Piece {
        let kind: Kind, x: CGFloat, vx: CGFloat, vy: CGFloat, tilt: Double, phase: Double, delay: Double, scale: CGFloat
    }

    static let approve = Color(red: 0.16, green: 0.63, blue: 0.29)
    static let life: Double = 3.4
    static let gravity: CGFloat = 260

    private let pieces: [Piece] = {
        let kinds: [Kind] = [.sheet, .check, .approved, .sheet, .check]
        return (0..<45).map { i in
            Piece(kind: kinds[i % kinds.count],
                  x: .random(in: 0.12...0.88), vx: .random(in: -45...45), vy: .random(in: -560 ... -380),
                  tilt: .random(in: -0.35...0.35), phase: .random(in: 0...6.28),
                  delay: Double(i) * 0.022 + .random(in: 0...0.12), scale: .random(in: 0.95...1.2))
        }
    }()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { g, size in
                let t = context.date.timeIntervalSince(start)
                let label = g.resolve(Text("✓ Approved").font(.system(size: 12, weight: .bold)).foregroundColor(.white))
                let labelSize = label.measure(in: CGSize(width: 200, height: 40))
                for p in pieces {
                    let s = t - p.delay
                    guard s > 0, s < Self.life else { continue }
                    let sway = sin(s * 2.4 + p.phase)
                    let x = p.x * size.width + p.vx * s + (p.kind == .sheet ? sway * 18 : sway * 6)
                    let y = size.height + 20 + p.vy * s + Self.gravity * s * s / 2
                    guard y < size.height + 60 else { continue }
                    var piece = g
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(p.tilt + (p.kind == .sheet ? sway * 0.35 : sway * 0.08)))
                    piece.scaleBy(x: p.scale, y: p.scale)
                    let fadeIn = min(1, s / 0.25), fadeOut = min(1, (Self.life - s) / 1.0)
                    piece.opacity = max(0, min(fadeIn, fadeOut))
                    draw(p.kind, in: &piece, label: label, labelSize: labelSize)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ kind: Kind, in g: inout GraphicsContext, label: GraphicsContext.ResolvedText, labelSize: CGSize) {
        switch kind {
        case .sheet:
            let page = CGRect(x: -14, y: -18, width: 28, height: 36)
            g.fill(Path(roundedRect: page, cornerRadius: 3), with: .color(.white))
            g.stroke(Path(roundedRect: page, cornerRadius: 3), with: .color(.black.opacity(0.18)), lineWidth: 0.8)
            for (i, w) in [18.0, 14.0, 16.0, 10.0].enumerated() {
                g.fill(Path(roundedRect: CGRect(x: -9, y: -11 + Double(i) * 5.5, width: w, height: 1.8), cornerRadius: 0.9),
                       with: .color(.black.opacity(0.22)))
            }
            g.fill(Path(ellipseIn: CGRect(x: 3, y: 8, width: 9, height: 9)), with: .color(Self.approve))
        case .check:
            g.fill(Path(ellipseIn: CGRect(x: -13, y: -13, width: 26, height: 26)), with: .color(Self.approve))
            var tick = Path()
            tick.move(to: CGPoint(x: -6, y: 0.5))
            tick.addLine(to: CGPoint(x: -1.6, y: 5))
            tick.addLine(to: CGPoint(x: 6.5, y: -4.5))
            g.stroke(tick, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        case .approved:
            let w = labelSize.width + 18, h = labelSize.height + 8
            g.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: h / 2),
                   with: .color(Self.approve))
            g.draw(label, at: .zero, anchor: .center)
        }
    }
}

struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Welcome to Diple",
                       detail: "Diple lives in your notch and tells you which pull requests are waiting on you. A minute here and it fits how you work.")
                .frame(maxWidth: .infinity)
            feature("eye", "A glance tells you", "The count in the notch is what needs you. Hover to open the queue.")
            feature("bell.badge", "Only what matters", "A reply to you, a review request, a failing check. Quiet outside your hours.")
            feature("sparkles", "Claude on your Mac", "Review with Claude, map a pull request, and let it resolve conflicts.")
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct GitHubStep: View {
    @ObservedObject var model: AppModel
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "Your GitHub account",
                       detail: "Diple borrows the token of the GitHub CLI, so there is nothing to sign in to here.")
            if !model.queue.viewer.isEmpty {
                Label("Signed in as \(model.queue.viewer)", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.green)
            } else {
                Text("Run this in a terminal, then check again:").font(.system(size: 13))
                HStack {
                    Text("gh auth login").font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    CopyButton(text: "gh auth login", label: "Copy")
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                Button {
                    checking = true
                    Task { await model.refresh(full: true); checking = false }
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text("Check again") }
                }
            }
        }
    }
}

struct TeamStep: View {
    @ObservedObject var model: AppModel
    @State private var orgs: [GitHubClient.Org]?
    @State private var teams: [GitHubClient.TeamRef]?

    private var picked: String { model.settings.primaryOrg ?? model.org }

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(title: "Who shows in Diple",
                       detail: "Pick the organization, and narrow the Team tab and the ranking to some of your GitHub teams. This only changes what you see. Who reviews what comes next.")
            if let orgs {
                if orgs.isEmpty {
                    Text("You are not in any organization, so there is no team to show. You can still use everything else.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    HStack(spacing: 10) {
                        ForEach(orgs) { org in orgCard(org) }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if let teams, !picked.isEmpty {
                if teams.isEmpty {
                    Text("Everyone in \(picked).").font(.system(size: 12.5)).foregroundStyle(.secondary)
                } else {
                    OnboardingCard {
                        Text("SHOW PEOPLE FROM").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        ForEach(teams) { t in
                            Toggle(isOn: teamBinding(t.slug)) {
                                Text(t.name).font(.system(size: 12.5))
                                + Text("  \(t.members) people").font(.system(size: 11.5)).foregroundColor(.secondary)
                            }
                        }
                        Text(model.settings.teams(in: picked).isEmpty ? "None picked: everyone in \(picked) shows."
                             : "Only these people show in Team and the ranking.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { orgs = await model.myOrganizations(); await loadTeams() }
        .onChange(of: model.settings.primaryOrg) { _, _ in Task { await loadTeams() } }
    }

    private func loadTeams() async {
        teams = nil
        guard !picked.isEmpty else { return }
        teams = await model.myTeams(in: picked)
    }

    private func orgCard(_ org: GitHubClient.Org) -> some View {
        let selected = org.login.lowercased() == picked.lowercased()
        return Button { model.settings.primaryOrg = org.login } label: {
            HStack(spacing: 10) {
                CachedAvatar(url: org.avatar) { Circle().fill(Color.secondary.opacity(0.2)) }
                    .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(org.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(org.login).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .frame(width: 185, height: 50)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                                                     lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func teamBinding(_ slug: String) -> Binding<Bool> {
        let id = "\(picked)/\(slug)"
        return Binding(
            get: { model.settings.teams.contains(id) },
            set: { on in
                if on { model.settings.teams.append(id) } else { model.settings.teams.removeAll { $0 == id } }
            }
        )
    }
}

struct ReviewsStep: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preview: RotationPreview

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(title: "Review rotation",
                       detail: "Hand each pull request to a few teammates instead of pinging everyone.")
            OnboardingCard(width: 480) { ReviewRotationPanel(model: model, preview: preview) }
        }
    }
}

struct NotchStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(title: "Make the notch yours", detail: "The notch and the code above change as you pick.")
            OnboardingCard {
                Toggle("Show the eye", isOn: $model.settings.showsEye)
                Toggle("Let it blink", isOn: $model.settings.eyeBlinks).disabled(!model.settings.showsEye)
                Divider()
                Picker("The count sits on the", selection: $model.settings.countSide) {
                    ForEach(CountSide.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Code theme", selection: $model.settings.codeTheme) {
                    ForEach(CodeTheme.all) { Text($0.name).tag($0.id) }
                }
                Text("Colors only the code in diffs, threads and AI reviews, shown above. The rest of Diple follows your Mac's appearance.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 13))
    }
}

struct DayPicker: View {
    @Binding var days: Set<Int>
    static let order: [(Int, String)] = [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.order, id: \.0) { day, name in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(String(name.prefix(1))).font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .help(name)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: days)
    }
}

struct HoursStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            StepHeader(title: "When you work",
                       detail: "Click the days in the preview above. Outside your days and hours, notifications go straight to Notification Center, without a banner or a sound. A reply to you still comes through.")
            Toggle("Quiet outside working hours", isOn: $model.settings.quietHoursOn)
                .toggleStyle(.switch)
            HStack(spacing: 10) {
                Text("From").foregroundStyle(.secondary)
                Picker("", selection: $model.settings.quietUntil) { hours }.labelsHidden().frame(width: 96)
                Text("to").foregroundStyle(.secondary)
                Picker("", selection: $model.settings.quietFrom) { hours }.labelsHidden().frame(width: 96)
            }
            .disabled(!model.settings.quietHoursOn)
            .opacity(model.settings.quietHoursOn ? 1 : 0.5)
        }
        .font(.system(size: 13))
    }

    private var hours: some View {
        ForEach(0..<24) { h in Text(String(format: "%02d:00", h)).tag(h) }
    }
}

struct RankingStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepHeader(title: "A ranking, if you want one",
                       detail: "Reviews are not a race. Keep it off, see only your own pace, or show the team board.")
            HStack(spacing: 10) {
                ForEach(RankingMode.allCases) { mode in
                    RankingChoice(mode: mode, selected: model.settings.rankingMode == mode) {
                        model.settings.rankingMode = mode
                    }
                }
            }
        }
    }
}

struct ExtrasStep: View {
    @ObservedObject var model: AppModel
    @StateObject private var login = LoginItem()

    var body: some View {
        VStack(spacing: 12) {
            StepHeader(title: "A few more things", detail: "You can change any of these later in Settings.")
            OnboardingCard {
                Toggle("Open Diple when you log in", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                Toggle("Sync right after you push from this Mac", isOn: $model.settings.syncsOnPush)
                Toggle("Sync early on GitHub notifications", isOn: $model.settings.syncsOnNotifications)
            }
        }
        .font(.system(size: 13))
        .onAppear { login.refresh() }
    }
}

struct TryItStep: View {
    let focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepHeader(title: "One trick",
                       detail: "Click the eye in the preview above. In the open notch it works the same way: it turns Focus on, and alerts wait until you click it again.")
            Label(focused ? "Focus is on. Click the eye again to turn it off." : "Go ahead, click it.",
                  systemImage: focused ? "moon.fill" : "hand.point.up.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(focused ? FocusCover.indigo : .secondary)
                .contentTransition(.opacity)
                .animation(.easeInOut, value: focused)
        }
    }
}

struct DoneStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepHeader(title: "You're all set", detail: "Here is what Diple will do. Settings has all of it.")
            row("person.3", model.org.isEmpty ? "No team" : "Team: \(model.org)"
                + (model.settings.teams(in: model.org).isEmpty ? "" : " · \(model.settings.teams(in: model.org).count) team(s)"))
            row("calendar", "Work days: \(DayPicker.order.filter { model.settings.workDays.contains($0.0) }.map(\.1).joined(separator: " "))")
            row("moon", model.settings.quietHoursOn
                ? "Quiet from \(String(format: "%02d:00", model.settings.quietFrom)) to \(String(format: "%02d:00", model.settings.quietUntil))"
                : "Never quiet")
            row(model.settings.rankingMode.icon, "Ranking: \(model.settings.rankingMode.title)")
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 13))
    }
}

struct OnboardingCard<Content: View>: View {
    var width: CGFloat = 380
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(width: width, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}
