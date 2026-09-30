import SwiftUI

enum FocusLook: String, CaseIterable, Identifiable {
    case terminal, breathing, pomodoro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terminal: "Terminal"
        case .breathing: "Breathing"
        case .pomodoro: "Pomodoro"
        }
    }

    static let key = "focusLook"

    static var saved: FocusLook {
        UserDefaults.standard.string(forKey: key).flatMap(FocusLook.init) ?? .terminal
    }
}

struct FocusCover: View {
    let since: Date
    var ended: Date?
    let look: FocusLook

    static let indigo = Color(red: 0.62, green: 0.58, blue: 1)
    static let round: TimeInterval = 25 * 60
    static let lingers: Duration = .milliseconds(1800)

    static let command = "heads-down"
    static let typeEvery = 0.07
    static let typingStarts = 0.25
    static var entered: TimeInterval { typingStarts + Double(command.count) * typeEvery + 0.35 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.86)
            switch look {
            case .terminal: terminal
            case .breathing: breathing
            case .pomodoro: pomodoro
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    static func lasted(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(max(0, Int(seconds))) s" : "\(Int(seconds / 60)) min"
    }

    private func focused(at now: Date) -> TimeInterval {
        (ended ?? now).timeIntervalSince(since)
    }

    private func caption(_ now: Date) -> some View {
        Text(ended == nil
             ? "focused · \(Self.lasted(focused(at: now))) · click the eye to come back"
             : "back · focused \(Self.lasted(focused(at: now)))")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.white.opacity(ended == nil ? 0.42 : 0.7))
            .contentTransition(.opacity)
    }

    private var mono: Font { .system(size: 13, weight: .semibold, design: .monospaced) }

    private func prompt(_ typed: String, cursor: Bool) -> some View {
        HStack(spacing: 0) {
            Text("$ ").foregroundStyle(Self.indigo)
            Text(typed).foregroundStyle(.white.opacity(0.9))
            Rectangle()
                .fill(Self.indigo)
                .frame(width: 7.5, height: 15)
                .padding(.leading, 1)
                .opacity(cursor ? 1 : 0)
        }
        .font(mono)
    }

    private func output(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(.white.opacity(0.5))
    }

    static let window = CGSize(width: 340, height: 132)

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34),
                         Color(red: 1, green: 0.74, blue: 0.18),
                         Color(red: 0.16, green: 0.79, blue: 0.25)], id: \.self) { c in
                    Circle().fill(c.opacity(0.75)).frame(width: 8, height: 8)
                }
                Spacer()
            }
            Text("~/diple — zsh")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(Color.white.opacity(0.05))
    }

    private var terminal: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let t = now.timeIntervalSince(since)
            let blink = Int(t / 0.53) % 2 == 0
            let entering = ended == nil && t < Self.entered
            let typed = ended == nil
                ? max(0, min(Self.command.count, Int((t - Self.typingStarts) / Self.typeEvery)))
                : Self.command.count
            let e = ended.map { now.timeIntervalSince($0) } ?? 0
            let exitTyped = ended == nil ? 0 : max(0, min(4, Int((e - 0.1) / 0.08)))
            let exited = ended != nil && e >= 0.1 + 4 * 0.08 + 0.3

            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    titleBar
                    Divider().overlay(Color.white.opacity(0.08))
                    VStack(alignment: .leading, spacing: 5) {
                        prompt(String(Self.command.prefix(typed)), cursor: entering)
                        if !entering {
                            output("✓ notifications paused · alerts off")
                                .foregroundStyle(Self.indigo.opacity(0.85))
                            prompt(String("exit".prefix(exitTyped)), cursor: !exited && (ended != nil || blink))
                        }
                        if exited {
                            output("back · focused \(Self.lasted(focused(at: now)))")
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(width: Self.window.width, height: Self.window.height)
                .background(Color(white: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

                caption(now)
                    .opacity(entering || ended != nil ? 0 : 1)
                    .animation(.easeOut(duration: 0.25), value: entering || ended != nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var breathing: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(since)
            let breath = (1 - cos(t * 2 * .pi / 4)) / 2
            ZStack {
                RadialGradient(
                    colors: [Self.indigo.opacity(0.10 + 0.22 * breath), .clear],
                    center: .center, startRadius: 0, endRadius: 150 + 40 * breath
                )
                VStack(spacing: 10) {
                    Image(systemName: ended == nil ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Self.indigo)
                        .scaleEffect(0.94 + 0.08 * breath)
                        .contentTransition(.symbolEffect(.replace))
                    caption(context.date)
                }
            }
        }
    }

    private var pomodoro: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let into = focused(at: context.date).truncatingRemainder(dividingBy: Self.round)
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.white.opacity(0.1), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: into / Self.round)
                        .stroke(Self.indigo, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: into)
                    Text(String(format: "%02d:%02d", Int(into) / 60, Int(into) % 60))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(width: 74, height: 74)
                caption(context.date)
            }
        }
    }
}
