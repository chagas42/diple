import SwiftUI

enum NotchState: Equatable {
    case hidden

    case active
    case open
    case alert(Event)

    var kind: String {
        switch self {
        case .hidden: "hidden"
        case .active: "active"
        case .open: "open"
        case .alert(let e): "alert-\(e.id)"
        }
    }

    static func == (a: NotchState, b: NotchState) -> Bool {
        switch (a, b) {
        case (.hidden, .hidden), (.active, .active), (.open, .open): true
        case let (.alert(x), .alert(y)): x.id == y.id
        default: false
        }
    }
}

struct NotchView: View {
    @ObservedObject var model: AppModel
    let state: NotchState
    let size: CGSize
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let gaze: CGPoint
    let blinking: Bool
    let onClose: () -> Void

    var body: some View {
        let _ = Metrics.shared.body("NotchView")
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(.black)
                content
                    .id(state.kind)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -10))
                                .animation(.easeOut(duration: 0.2).delay(0.08)),
                            removal: .opacity.animation(.easeIn(duration: 0.08))
                        )
                    )
            }
            .frame(width: size.width, height: size.height)

            .clipShape(shape)
            .contextMenu {
                Button("Settings…") { Windows.shared.openSettings(model) }
                Button("Janela main") { Windows.shared.openMain(model) }
                Divider()
                Button("Quit Diple") { NSApplication.shared.terminate(nil) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: size)
        .animation(.easeOut(duration: 0.22), value: state.kind)
        .animation(.bouncy(duration: 0.35), value: model.count)
    }

    private var shape: PanelShape {
        PanelShape(flare: flare, base: radius)
    }

    private var radius: CGFloat {
        switch state {
        case .hidden, .active: 10
        case .open, .alert: 22
        }
    }

    private var flare: CGFloat {
        switch state {
        case .hidden, .active: 0
        case .open, .alert: 16
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .hidden:
            Color.clear
        case .active:
            wings
        case .open:
            open
        case .alert(let e):
            alert(e)
        }
    }

    private var wings: some View {
        HStack(spacing: 0) {
            EyeView(gaze: gaze, blinking: blinking, width: 15)
                .opacity(model.count > 0 ? 1 : 0.42)
                .animation(.easeOut(duration: 0.25), value: model.count > 0)
                .frame(maxWidth: .infinity)
            Spacer(minLength: notchWidth)
                .frame(width: notchWidth)
            Text("\(model.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(model.count > 0 ? 0.92 : 0.34))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.count)
                .contentTransition(.numericText(value: Double(model.count)))
                .frame(maxWidth: .infinity)
        }
        .frame(height: notchHeight)
    }

    private var open: some View {
        VStack(spacing: 0) {
            topStrip
            openBody
        }
    }

    private var topStrip: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                EyeView(gaze: gaze, blinking: blinking, width: 15)
                    .padding(.trailing, 2)
                ForEach(AppModel.NotchTab.allCases) { tab in
                    Button { model.notchTab = tab } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(model.notchTab == tab ? 0.95 : 0.42))
                            .frame(width: 30, height: 26)
                            .background(
                                Capsule().fill(
                                    model.notchTab == tab
                                        ? Color.white.opacity(0.15) : .white.opacity(0.001)
                                )
                            )

                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 14 + flare)
            .frame(maxWidth: .infinity)

            Spacer(minLength: notchWidth).frame(width: notchWidth)

            HStack(spacing: 7) {
                Spacer(minLength: 0)
                iconButton("macwindow") {
                    Windows.shared.openMain(model)
                    onClose()
                }
                if model.loading || model.refreshingTab != nil {
                    ProgressView().controlSize(.small).tint(.white).frame(width: 22)
                } else {
                    iconButton("arrow.clockwise") {
                        let tab = model.notchTab
                        Task {
                            await model.refresh()
                            model.loadTab(tab, force: true)
                        }
                    }
                }
                iconButton("gearshape") {
                    Windows.shared.openSettings(model)
                    onClose()
                }
                iconButton("xmark") { onClose() }
            }
            .padding(.trailing, 14 + flare)
            .frame(maxWidth: .infinity)
        }
        .frame(height: notchHeight)
    }

    private func iconButton(_ name: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.1), in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var openBody: some View {
        Group {
            switch model.notchTab {
            case .queue:
                HStack(spacing: 12) { summaryCard; queueCard }
            case .team:
                TeamTab(model: model)
            case .ranking:
                RankTab(model: model)
            case .activity:
                ActivityTab(model: model)
            }
        }
        .padding(.horizontal, 16 + flare)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: model.notchTab, initial: true) { model.loadTab(model.notchTab) }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(model.count)")
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(model.count)))
            Text(model.count == 1 ? "waiting on you" : "waiting on you")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 2)

            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: 5) {
                stat("yours", model.queue.mine.count)
                stat("to review", model.queue.toReview.count)
                stat("following", model.queue.following.count)
            }
        }
        .padding(14)
        .frame(width: 176, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func stat(_ label: String, _ n: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(n)")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(AppModel.Tab.allCases) { t in
                    let on = model.tab == t
                    Button { model.tab = t } label: {
                        HStack(spacing: 4) {
                            Text(t.title)
                                .font(.system(size: 10, weight: on ? .semibold : .regular))
                            Text("\(model.count(t))")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(
                                    t == .needsYou && model.count(t) > 0
                                        ? .orange : .white.opacity(on ? 0.5 : 0.3)
                                )
                        }
                        .foregroundStyle(.white.opacity(on ? 0.95 : 0.42))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(on ? 0.14 : 0))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if model.prs(model.tab).count > 4 {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .animation(.easeOut(duration: 0.15), value: model.tab)
            .padding(.horizontal, 13)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if let problem = model.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                    Text(problem)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.prs(model.tab).isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(model.tab == .needsYou ? "Nothing waiting on you" : "Nothing in \(model.tab.title)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.prs(model.tab).enumerated()), id: \.element.id) { i, pr in
                            if i > 0 {
                                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                                    .padding(.horizontal, 13)
                            }
                            Button { model.open(pr) } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(pr.title)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        HStack(spacing: 6) {
                                            if let r = model.needsReason(pr) {
                                                reasonChip(r)
                                            }
                                            Text(meta(pr))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.45))
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Text(pr.updatedAt.formatted(.relative(presentation: .numeric)))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func meta(_ pr: PR) -> String {
        let base = "\(pr.repo.split(separator: "/").last.map(String.init) ?? pr.repo) #\(pr.number)"
        if let c = pr.lastComment {
            return "\(base) · \(c.author)\(c.location.map { " at \($0)" } ?? "")"
        }
        return base
    }

    @ViewBuilder
    private func soundNote(_ sound: Settings.AlertSound) -> some View {
        let note: (String, String)? = switch sound {
        case .plays(let name): ("speaker.wave.2.fill", name)
        case .quietHours:      ("moon.fill", "silenced · quiet hours")
        case .muted:           ("speaker.slash.fill", "muted in Settings")
        case .silent:          nil
        }
        if let (icon, text) = note {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 8.5))
                Text(text).font(.system(size: 10))
            }
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func alert(_ e: Event) -> some View {
        VStack(spacing: 0) {
            alertStrip(e)
            alertBody(e)
        }
    }

    private func alertStrip(_ e: Event) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: e.kind.glyph)
                    .font(.system(size: 11))
                    .foregroundStyle(colorFor(e.kind))
                Text(e.kind.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 14 + flare)
            .frame(maxWidth: .infinity)

            Spacer(minLength: notchWidth).frame(width: notchWidth)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                soundNote(model.settings.alertSound(e))
                iconButton("xmark") { onClose() }
            }
            .padding(.trailing, 14 + flare)
            .frame(maxWidth: .infinity)
        }
        .frame(height: notchHeight)
    }

    private func alertBody(_ e: Event) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Circle()
                .fill(colorFor(e.kind).opacity(0.16))
                .overlay(
                    Image(systemName: e.kind.glyph)
                        .font(.system(size: 15))
                        .foregroundStyle(colorFor(e.kind))
                )
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 5) {
                Text(e.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(e.body)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(e.url)
                        onClose()
                    } label: {
                        Text("Open PR")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 15).padding(.vertical, 7)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onClose()
                    } label: {
                        Text("Later")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 18 + flare)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reasonChip(_ r: AppModel.NeedsReason) -> some View {
        HStack(spacing: 3) {
            Image(systemName: r.kind.glyph).font(.system(size: 8, weight: .bold))
            Text(r.label).font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(colorFor(r.kind).opacity(0.95))
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(colorFor(r.kind).opacity(0.14)))
    }

    private func colorFor(_ t: EventKind) -> Color {
        switch t {
        case .repliedToYou: .orange
        case .commented:      .purple
        case .reviewRequested:   .blue
        case .checkFailed:     .red
        case .approved:       .green
        }
    }
}
