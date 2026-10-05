import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pane: SettingsPane?

    init(model: AppModel, pane: SettingsPane = .general) {
        self.model = model
        _pane = State(initialValue: pane)
    }

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

            Section("Focus") {
                Toggle("Quiet while a macOS Focus is on", isOn: $model.settings.followsFocus)
                Text("While focused, the notch drops no alerts, the eye stops blinking and half closes, the panel is covered, and notifications go straight to Notification Center without a sound. Click the eye in the open notch to focus from Diple too.")
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
                            Text(quantos == 1 ? "1 pull request" : "\(quantos) pull requests")
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
                HStack {
                    Picker("Every", selection: $model.settings.interval) {
                        Text("30 seconds").tag(TimeInterval(30))
                        Text("1 minute").tag(TimeInterval(60))
                        Text("5 minutes").tag(TimeInterval(300))
                        Text("15 minutes").tag(TimeInterval(900))
                    }
                    Button("Sync Now") { Task { await model.refreshVisible() } }
                        .disabled(model.loading)
                }
                Text("Each sync spends about \(pointsPerSync) of the 5,000 GitHub API points your account "
                     + "gets per hour, so \(pointsPerHour) an hour at this interval. "
                     + "gh and anything else using your token draw from the same budget.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Toggle("Sync early on GitHub notifications", isOn: $model.settings.syncsOnNotifications)
                Text("Checks your GitHub notifications every minute, which costs no sync points, and syncs right away when one of your pull requests moves.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 10) {
                    ForEach(RankingMode.allCases) { mode in
                        RankingChoice(mode: mode, selected: model.settings.rankingMode == mode) {
                            model.settings.rankingMode = mode
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Ranking")
            } footer: {
                Text("Reviews are counted from GitHub either way. This only decides what the notch shows you.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                LabeledContent("Version", value: updates.summary)
                HStack {
                    updateStatus
                    Spacer()
                    Button("Release Notes") { NSWorkspace.shared.open(updates.releaseNotes) }
                    if case .available(_, let page) = updates.state {
                        if updates.canInstall {
                            Button("Update Now") { updates.install() }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Download") { NSWorkspace.shared.open(page) }
                        }
                    } else {
                        Button("Check for Updates") { Task { await updates.check() } }
                            .disabled(updates.state == .checking || isInstalling)
                    }
                }
                if case .available = updates.state {
                    if !updates.canInstall, !updates.isDevelopment, updates.viaHomebrew {
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
                if case .installFailed(_, let page) = updates.state {
                    HStack {
                        Text("The update did not install.")
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Download") { NSWorkspace.shared.open(page) }
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
    private var pointsPerSync: Int { Query.heartbeatSearches.count }

    private var pointsPerHour: Int { pointsPerSync * Int(3600 / model.settings.interval) }

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
        case .installing(let version):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Installing \(version)… Diple will restart.").foregroundStyle(.secondary)
            }
        case .installFailed(let version, _):
            Text("Version \(version) is out").foregroundStyle(.orange)
        }
    }

    private var isInstalling: Bool {
        if case .installing = updates.state { true } else { false }
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
    @State private var scanning = false

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
                Toggle("Push resolved conflicts without asking", isOn: $model.settings.pushesResolvedConflicts)
                Text("Resolve with Claude merges the base branch into the pull request in its own worktree. "
                     + "Claude may edit files there and read git; it never commits, pushes or reaches the network. "
                     + "Diple runs the project's tests, commits the merge and pushes it, never with force. "
                     + "Turned off, Diple stops before pushing and waits for you.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Resolving conflicts")
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
                HStack {
                    Text(model.settings.reposFolders.count == 1 ? "Folder with your clones" : "Folders with your clones")
                    Spacer()
                    if scanning {
                        ProgressView().controlSize(.small)
                    } else if !model.settings.reposFolders.isEmpty {
                        Button("Rescan") { scan() }
                    }
                    if model.settings.reposFolders.isEmpty {
                        Button("Choose…") { addReposFolders() }
                            .disabled(scanning)
                    } else {
                        Button { addReposFolders() } label: { Image(systemName: "plus") }
                            .help("Add a folder")
                            .disabled(scanning)
                    }
                }
                ForEach(model.settings.reposFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(atalho(folder)).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        if !scanning {
                            Text(foundCount(in: folder))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Button { removeReposFolder(folder) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Stop scanning this folder")
                            .disabled(scanning)
                    }
                }
                if !model.settings.reposFolders.isEmpty, !scanning, !repos.isEmpty {
                    Text(scanSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if repos.isEmpty {
                    Text("The queue has not loaded yet.").foregroundStyle(.secondary)
                }
                ForEach(repos, id: \.self) { r in
                    HStack {
                        Text(r).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        if let u = model.settings.localPath(r) {
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
                     + "~/.diple/worktrees — your checkout is never touched. "
                     + "Folders with your clones are searched four levels deep and "
                     + "each clone is matched by its GitHub remotes; a path you chose by hand always wins.")
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

    private func foundCount(in folder: String) -> String {
        let found = RepoScan.found(in: folder, scanned: model.settings.scannedRepoPaths)
        return "\(found) \(found == 1 ? "repository" : "repositories")"
    }

    private var scanSummary: String {
        let matched = RepoScan.matched(repos, manual: model.settings.repoPaths,
                                       scanned: model.settings.scannedRepoPaths)
        return "\(matched) of the \(repos.count) below matched."
    }

    private func addReposFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan"
        if let last = model.settings.reposFolders.last {
            panel.directoryURL = URL(fileURLWithPath: last)
        }
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.map(\.path).filter { !model.settings.reposFolders.contains($0) }
        guard !added.isEmpty else { return }
        model.settings.reposFolders += added
        scan()
    }

    private func removeReposFolder(_ folder: String) {
        model.settings.reposFolders.removeAll { $0 == folder }
        scan()
    }

    private func scan() {
        let folders = model.settings.reposFolders.map { URL(fileURLWithPath: $0) }
        scanning = true
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                RepoScan.scan(folders)
            }.value
            model.settings.scannedRepoPaths = found
            scanning = false
        }
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

struct RankingChoice: View {
    let mode: RankingMode
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(height: 20)
                Text(mode.title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(mode.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

