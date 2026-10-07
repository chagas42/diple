import SwiftUI
import AppKit

enum Onboarding {
    static let version = 1

    enum Step: Int, CaseIterable {
        case welcome, github, team, notch, hours, ranking, extras, tryIt, done
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

    var body: some View {
        VStack(spacing: 0) {
            NotchStage(model: model, step: step, eye: eye, focused: previewFocused) { Task { await poke() } }
                .frame(height: 236)
            ZStack(alignment: .top) {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 48)
            .padding(.top, 24)
            .clipped()
            footer
        }
        .overlay { if let celebration { Confetti(start: celebration) } }
        .frame(width: 720, height: 652)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .onAppear { step = start }
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
                ForEach(Onboarding.Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s == step ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            Spacer()
            if let back = Onboarding.Step(rawValue: step.rawValue - 1), step != .done {
                Button("Back") { go(back) }
            }
            if step == .done {
                LaunchButton(title: "Start using Diple", presses: celebrates) {
                    celebration = Date()
                    Task {
                        try? await Task.sleep(for: .milliseconds(2600))
                        finish()
                    }
                }
            } else if let next = Onboarding.Step(rawValue: step.rawValue + 1) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
    }
}

struct NotchStage: View {
    @ObservedObject var model: AppModel
    let step: Onboarding.Step
    @ObservedObject var eye: EyeState
    let focused: Bool
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
    static let command = "gh auth status"
    static let avatars: [CGFloat] = [284, 322, 360, 398, 436]

    private var settings: Settings { model.settings }
    private var showsEye: Bool { settings.showsEye || step == .tryIt }

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
        CGPoint(x: max(-1, min(1, (p.x - Self.eyeAt.x) / 240)), y: max(-1, min(1, (p.y - Self.eyeAt.y) / 120)))
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
        withAnimation { showsCursor = step != .done && step != .github }
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
            case .notch:
                for p in [CGPoint(x: 200, y: 90), CGPoint(x: 520, y: 60), CGPoint(x: 360, y: 180)] {
                    guard !Task.isCancelled else { return }
                    await move(p, 1.2)
                    await pause(0.4)
                }
            case .hours:
                await move(CGPoint(x: 500, y: 150), 0.8)
                for i in 0...7 {
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { lit = i }
                    await pause(0.16)
                }
                await pause(1.6)
                withAnimation(.easeOut(duration: 0.3)) { lit = 0 }
                await pause(0.4)
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
            wing(showEye: showsEye && (side == .right || step == .tryIt), showCount: side == .left && step != .tryIt)
            Spacer(minLength: 120)
            wing(showEye: false, showCount: side == .right || step == .tryIt)
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
                    .overlay {
                        if step == .tryIt, !focused {
                            Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                                .frame(width: 34, height: 34)
                                .scaleEffect(ring ? 1.25 : 0.9)
                                .opacity(ring ? 0 : 0.9)
                        }
                    }
                    .overlay(alignment: .bottomLeading) { Complaint(eye: eye).offset(x: 6, y: 22) }
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
        case .notch:
            Text("Changes show here as you make them.")
                .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
        case .hours:
            HStack(spacing: 4) {
                ForEach(Array(DayPicker.order.enumerated()), id: \.offset) { i, d in
                    let on = settings.workDays.contains(d.0)
                    Text(String(d.1.prefix(1))).font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(on ? Color.accentColor : .white.opacity(0.08)))
                        .foregroundStyle(.white)
                        .scaleEffect(i < lit ? 1.12 : 1)
                        .opacity(i < lit ? 1 : 0.55)
                }
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
    @State private var running = false
    @State private var shakes = 0

    var body: some View {
        Button(action: press) { label }
        .buttonStyle(.plain)
        .task { if presses { try? await Task.sleep(for: .seconds(3)); press() } }
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
        .keyboardShortcut(.defaultAction)
    }

    private func press() {
            guard !running else { return }
            running = true
            withAnimation(.easeIn(duration: 1.1)) { progress = 1 }
            Task {
                try? await Task.sleep(for: .milliseconds(1150))
                shakes += 1
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                try? await Task.sleep(for: .milliseconds(420))
                onDone()
            }
    }

    private var label: some View {
            Text(running ? (progress < 1 ? "Getting ready…" : "Here we go") : title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.accentColor.opacity(running ? 0.35 : 1))
                            Capsule().fill(Color.accentColor).frame(width: g.size.width * progress)
                        }
                    }
                }
                .contentShape(Capsule())
    }
}

struct Confetti: View {
    let start: Date

    struct Piece {
        let x: CGFloat, vx: CGFloat, vy: CGFloat, spin: Double, size: CGSize, color: Color, delay: Double
    }

    private let pieces: [Piece] = {
        let colors: [Color] = [.accentColor, .pink, .orange, .yellow, .green, .mint, .purple]
        let cannons: [(x: CGFloat, vx: ClosedRange<CGFloat>)] = [(0.04, 120...520), (0.96, -520 ... -120), (0.5, -260...260)]
        return (0..<240).map { i in
            let c = cannons[i % cannons.count]
            return Piece(x: c.x, vx: .random(in: c.vx), vy: .random(in: -1180 ... -700),
                         spin: .random(in: -10...10), size: CGSize(width: .random(in: 6...11), height: .random(in: 10...18)),
                         color: colors[i % colors.count], delay: .random(in: 0...0.35))
        }
    }()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { g, size in
                let t = context.date.timeIntervalSince(start)
                for p in pieces {
                    let s = t - p.delay
                    guard s > 0, s < 3 else { continue }
                    let x = p.x * size.width + p.vx * s
                    let y = size.height + p.vy * s + 900 * s * s / 2
                    guard y < size.height + 20 else { continue }
                    var piece = g
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(p.spin * s))
                    piece.opacity = max(0, 1 - s / 3)
                    piece.fill(Path(CGRect(origin: CGPoint(x: -p.size.width / 2, y: -p.size.height / 2), size: p.size)),
                               with: .color(p.color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(title: "Welcome to Diple",
                       detail: "Diple lives in your notch and tells you which pull requests are waiting on you. A minute here and it fits how you work.")
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
        VStack(alignment: .leading, spacing: 12) {
            StepHeader(title: "Your team",
                       detail: "Pick the organization Diple ranks and shows as your team. Narrow it to your GitHub teams, or leave it as everyone.")
            if let orgs {
                if orgs.isEmpty {
                    Text("You are not in any organization, so there is no team to show. You can still use everything else.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        ForEach(orgs) { org in orgCard(org) }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if let teams, !picked.isEmpty {
                Text("TEAMS IN \(picked.uppercased())").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).padding(.top, 6)
                if teams.isEmpty {
                    Text("Everyone in \(picked).").font(.system(size: 12.5)).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
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
            VStack(spacing: 6) {
                CachedAvatar(url: org.avatar) { Circle().fill(Color.secondary.opacity(0.2)) }
                    .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                Text(org.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(org.login).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 130, height: 96)
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

struct NotchStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepHeader(title: "Make the notch yours", detail: "Everything here changes the preview above as you go.")
            Toggle("Show the eye", isOn: $model.settings.showsEye)
            Toggle("Let it blink", isOn: $model.settings.eyeBlinks).disabled(!model.settings.showsEye)
            Picker("The count sits on the", selection: $model.settings.countSide) {
                ForEach(CountSide.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Code theme", selection: $model.settings.codeTheme) {
                ForEach(CodeTheme.all) { Text($0.name).tag($0.id) }
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
                    Text(name).font(.system(size: 12, weight: .semibold))
                        .frame(width: 42, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.accentColor : Color.primary.opacity(0.06)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: days)
    }
}

struct HoursStep: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeader(title: "When you work",
                       detail: "Outside these days and hours, notifications go straight to Notification Center, without a banner or a sound. A reply to you still comes through.")
            Text("WORK DAYS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            DayPicker(days: $model.settings.workDays)
            Toggle("Quiet outside working hours", isOn: $model.settings.quietHoursOn)
            HStack {
                Picker("From", selection: $model.settings.quietUntil) { hours }
                Picker("to", selection: $model.settings.quietFrom) { hours }
            }
            .disabled(!model.settings.quietHoursOn)
            .frame(maxWidth: 360)
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
        VStack(alignment: .leading, spacing: 12) {
            StepHeader(title: "A few more things", detail: "You can change any of these later in Settings.")
            Toggle("Open Diple when you log in", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
            Toggle("Sync right after you push from this Mac", isOn: $model.settings.syncsOnPush)
            Toggle("Sync early on GitHub notifications", isOn: $model.settings.syncsOnNotifications)
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
