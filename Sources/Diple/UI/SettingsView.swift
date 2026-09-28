import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            NotificationsPane(model: model)
                .tabItem { Label("Notifications", systemImage: "bell") }
            ReposPane(model: model)
                .tabItem { Label("Repositories", systemImage: "book.closed") }

            AppearanceSettings(model: model)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            ClaudePane(model: model)
                .tabItem { Label("Claude", systemImage: "sparkles") }
            AccountPane(model: model)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            PrivacyPane(model: model)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 620, height: 460)
    }
}

struct NotificationsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            if model.isQuietNow {
                Section {
                    HStack(spacing: 9) {
                        Image(systemName: "moon.fill").foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Quiet hours are on right now")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("Only direct replies get through. "
                                 + "Test ignores this on purpose.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }

            Section {
                ForEach(EventKind.allCases, id: \.self) { t in
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(
                            get: { model.settings.alerts(t) },
                            set: { model.settings.alerts[t.rawValue] = $0 }
                        ))
                        .labelsHidden()

                        VStack(alignment: .leading, spacing: 1) {
                            Text(title(t)).font(.system(size: 12.5))
                            HStack(spacing: 5) {
                                Text(tooltip(t))
                                if model.settings.sound(t) == nil, model.settings.alerts(t) {
                                    Text("· arrives silent")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("", selection: Binding(
                            get: { model.settings.sound(t) ?? "" },
                            set: { model.settings.sounds[t.rawValue] = $0 }
                        )) {
                            Text("None").tag("")
                            Divider()
                            ForEach(Settings.availableSounds, id: \.self) { s in
                                Text(s).tag(s)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .disabled(!model.settings.alerts(t))

                        Button {
                            if let s = model.settings.sound(t) { NSSound(named: s)?.play() }
                        } label: { Image(systemName: "speaker.wave.2.fill") }
                            .disabled(model.settings.sound(t) == nil)
                            .help("Play the sound only")

                        Button("Test") { Task { await model.sendTestEvent(t) } }
                            .help("Fires a real alert: banner, sound and the notch animation")
                    }
                    .padding(.vertical, 2)
                }
                HStack {
                    Button("Test all in sequence") {
                        Task {
                            for t in EventKind.allCases where model.settings.alerts(t) {
                                await model.sendTestEvent(t)
                                try? await Task.sleep(for: .seconds(2.5))
                            }
                        }
                    }
                    Spacer()
                }
            } header: {
                Text("When this happens")
            } footer: {
                Text("What is off still lands in the queue — it just will not interrupt. "
                     + "Test fires a real alert: banner, sound and the notch opening.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section("Quiet hours") {
                Toggle("Mute outside these hours", isOn: $model.settings.quietHoursOn)
                HStack {
                    Text("From")
                    Picker("", selection: $model.settings.quietFrom) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }.labelsHidden().frame(width: 90)
                    Text("to")
                    Picker("", selection: $model.settings.quietUntil) {
                        ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                    }.labelsHidden().frame(width: 90)
                    Spacer()
                }
                .disabled(!model.settings.quietHoursOn)
                Toggle("Weekends too", isOn: $model.settings.quietOnWeekends)
                    .disabled(!model.settings.quietHoursOn)
                Text("A direct reply to you always gets through.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func title(_ t: EventKind) -> String {
        switch t {
        case .repliedToYou: "Someone replied to you in a thread"
        case .commented:      "Someone commented on your PR"
        case .reviewRequested:   "Someone requested your review"
        case .checkFailed:     "A check failed on one of your PRs"
        case .approved:       "Someone approved your PR"
        case .newPullRequest: "A pull request opened in a repository you watch"
        }
    }

    private func tooltip(_ t: EventKind) -> String {
        switch t {
        case .repliedToYou: "The only one that breaks quiet hours."
        case .commented:      "PR conversation and inline code comments."
        case .reviewRequested:   "Directly to you, or through one of your teams."
        case .checkFailed:     "Only on the first failure; retries do not repeat."
        case .approved:       "Usually enough to see when you open the queue."
        case .newPullRequest: "Only repositories you starred, only what opens from now on, and never a draft."
        }
    }
}

struct ReposPane: View {
    @ObservedObject var model: AppModel

    private var repos: [(String, Int)] {
        Dictionary(grouping: model.queue.all, by: \.repo)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        Form {
            Section {
                if repos.isEmpty {
                    Text("The queue has not loaded yet.").foregroundStyle(.secondary)
                }
                ForEach(repos, id: \.0) { name, quantos in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).font(.system(size: 12.5, design: .monospaced))
                            Text("\(quantos) na queue")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Muted", isOn: Binding(
                            get: { model.settings.mutedRepos.contains(name) },
                            set: { on in
                                if on { model.settings.mutedRepos.insert(name) }
                                else { model.settings.mutedRepos.remove(name) }
                            }
                        ))
                    }
                }
            } header: {
                Text("Repositories in your queue")
            } footer: {
                Text("Muted still shows in the list; it just stops alerting.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AccountPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("GitHub") {
                LabeledContent("Account", value: model.queue.viewer.isEmpty ? "—" : model.queue.viewer)
                LabeledContent("Token") {
                    Text("borrowed from gh")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("RawRateLimit restante") {
                    Text("\(model.queue.rateLimitLeft) de 5000")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text("Diple stores no token. It calls `gh auth token` on every request.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section("Sync") {
                Picker("Every", selection: $model.settings.interval) {
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("15 minutes").tag(TimeInterval(900))
                }
                Text("One sync costs 1 point of 5000 per hour.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Sincronizar now") { Task { await model.refresh() } }
                        .disabled(model.loading)
                    Spacer()
                    Button("Quit Diple") { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ClaudePane: View {
    @ObservedObject var model: AppModel

    private var repos: [String] {
        Array(Set(model.queue.all.map(\.repo))).sorted()
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 9) {
                    Circle()
                        .fill(temClaude ? .green : .orange)
                        .frame(width: 7, height: 7)
                    Text(temClaude ? "claude found on PATH"
                                   : "claude is not on PATH")
                    Spacer()
                }
                Picker("Mark comments as drafted by Diple", selection: Binding(
                    get: { model.settings.attributionMode },
                    set: { model.settings.attribution = $0.rawValue }
                )) {
                    ForEach(Attribution.allCases) { Text($0.label).tag($0) }
                }
                Text(model.settings.attributionMode.blurb)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Review model", selection: $model.settings.aiModel) {
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }
                Picker("Map model", selection: Binding(
                    get: { model.settings.mapAIModel },
                    set: { model.settings.mapModel = $0 }
                )) {
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }
                LabeledContent(
                    "Deep review",
                    value: DeepReview.available ? "on · ~/.claude/skills/diple-review" : "off"
                )
                Text("Diple has no AI of its own. It runs the claude on your machine, "
                     + "with your account and your skills. Tokens count against your plan.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Session")
            }

            Section {
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ALLOWED")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.green)
                        Text("Read · Grep · Glob · Skill\nBash(git diff/log/show/status)")
                            .font(.system(size: 10.5, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BLOCKED")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.red)
                        Text("Write · Edit · WebFetch\nBash(gh/push/commit/curl)")
                            .font(.system(size: 10.5, design: .monospaced))
                    }
                    Spacer()
                }
            } header: {
                Text("Session limits")
            } footer: {
                Text("Cannot be turned off: the session starts without write tools, "
                     + "so the AI has no way to publish anything.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Open files in", selection: Binding(
                    get: { model.settings.openIn },
                    set: { model.settings.editor = $0.rawValue }
                )) {
                    ForEach(Editor.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Map skill", value: MapSkill.resolve().source)
            } header: {
                Text("PR map")
            } footer: {
                Text("A click opens the file at the PR head while its worktree is still around, "
                     + "then in your clone, then on GitHub. ⌥-click always opens GitHub. "
                     + "To change how the map is drawn, put your own skill at ~/.claude/skills/diple-map.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section {
                if repos.isEmpty {
                    Text("The queue has not loaded yet.").foregroundStyle(.secondary)
                }
                ForEach(repos, id: \.self) { r in
                    HStack {
                        Text(r).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        if let u = Worktree.localPath(r, configured: model.settings.repoPaths) {
                            Text(atalho(u.path))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Choose…") { escolher(r) }
                        }
                    }
                }
            } header: {
                Text("Where each repository lives")
            } footer: {
                Text("Diple looks in @work, @studies, dev, work, Developer, "
                     + "code and src. Each review runs in a throwaway worktree in "
                     + "~/.diple/worktrees — your checkout is never touched.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var temClaude: Bool { Tools.find("claude") != nil }

    private func atalho(_ p: String) -> String {
        p.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func escolher(_ repo: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Usar esta folder"
        if panel.runModal() == .OK, let u = panel.url {
            model.settings.repoPaths[repo] = u.path
        }
    }
}
