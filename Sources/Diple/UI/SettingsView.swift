import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                Label { Text(p.title) } icon: { SettingsIcon(pane: p) }
                    .tag(p)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle((pane ?? .general).title)
        }
        .frame(minWidth: Self.minimum.width, maxWidth: .infinity,
               minHeight: Self.minimum.height, maxHeight: .infinity)
    }

    @ViewBuilder private var detail: some View {
        switch pane ?? .general {
        case .general:       GeneralPane(model: model)
        case .notifications: NotificationsPane(model: model)
        case .repositories:  ReposPane(model: model)
        case .appearance:    AppearanceSettings(model: model)
        case .claude:        ClaudePane(model: model)
        case .account:       AccountPane(model: model)
        case .privacy:       PrivacyPane(model: model)
        }
    }

    static let minimum = CGSize(width: 820, height: 520)
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, notifications, repositories, appearance, claude, account, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:       "General"
        case .notifications: "Notifications"
        case .repositories:  "Repositories"
        case .appearance:    "Appearance"
        case .claude:        "Claude"
        case .account:       "Account"
        case .privacy:       "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .general:       "gearshape.fill"
        case .notifications: "bell.badge.fill"
        case .repositories:  "book.closed.fill"
        case .appearance:    "paintpalette.fill"
        case .claude:        "sparkles"
        case .account:       "person.crop.circle.fill"
        case .privacy:       "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general:       .gray
        case .notifications: .red
        case .repositories:  .indigo
        case .appearance:    .blue
        case .claude:        .orange
        case .account:       .teal
        case .privacy:       .blue
        }
    }
}

struct SettingsIcon: View {
    let pane: SettingsPane

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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

            Section("Your reviews") {
                Toggle("Show each review you send in the notch", isOn: $model.settings.showsReviews)
                Text("A thin strip slides out of the notch with the PR, and a sheet drops from "
                     + "the count onto how many you have reviewed today.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("One stack per pull request", isOn: $model.settings.stackPerPR)
                Text(model.settings.stackPerPR
                     ? "Each PR gets its own stack in Notification Center."
                     : "Every Diple notification shares one stack, the way Slack's do.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notification Center")
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

struct GeneralPane: View {
    @ObservedObject var model: AppModel
    @StateObject private var login = LoginItem()
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        Form {
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

            Section("Diple") {
                LabeledContent("Version", value: updates.summary)
                if !updates.isDevelopment {
                    HStack {
                        updateStatus
                        Spacer()
                        if case .available(_, let page) = updates.state {
                            Button("Download") { NSWorkspace.shared.open(page) }
                        }
                        Button("Check now") { Task { await updates.check() } }
                            .disabled(updates.state == .checking)
                    }
                    if case .available = updates.state, updates.viaHomebrew {
                        HStack {
                            Text("brew upgrade --cask diple")
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew upgrade --cask diple", forType: .string)
                            }
                        }
                    }
                }
            }

            Section("Startup") {
                Toggle("Start at login", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                if login.awaitsApproval {
                    HStack {
                        Text("macOS is waiting for you to allow Diple in Login Items.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { login.openLoginItems() }
                    }
                }
                if let failure = login.failure {
                    Text(failure)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Button("Sync now") { Task { await model.refresh() } }
                        .disabled(model.loading)
                    Button("Send feedback…") { Windows.shared.openFeedback(model, feature: .general) }
                    Spacer()
                    Button("Quit Diple") { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            login.refresh()
            if updates.state == .idle || updates.state == .failed { Task { await updates.check() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }
}

extension GeneralPane {
    @ViewBuilder private var updateStatus: some View {
        switch updates.state {
        case .idle, .checking:
            Text("Checking for updates…").foregroundStyle(.secondary)
        case .current:
            Text("Up to date").foregroundStyle(.secondary)
        case .available(let version, _):
            Text("Version \(version) is out").foregroundStyle(.orange)
        case .failed:
            Text("Could not reach GitHub").foregroundStyle(.secondary)
        }
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
                LabeledContent("Rate limit left") {
                    Text("\(model.queue.rateLimitLeft) of 5000")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text("Diple stores no token. It calls `gh auth token` on every request.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
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
        panel.prompt = "Use This Folder"
        if panel.runModal() == .OK, let u = panel.url {
            model.settings.repoPaths[repo] = u.path
        }
    }
}
