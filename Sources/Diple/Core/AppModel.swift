import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    var onEvent: ((Event) -> Void)?
    var onCountChange: (() -> Void)?

    @Published private(set) var queue = Queue()
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var hasPermission = false
    @Published private(set) var unread: Set<String> = []

    @Published var notchTab: NotchTab = .queue
    @Published private(set) var team: [Person] = []
    @Published private(set) var ranking: [RankRow] = []
    @Published private(set) var activity: [ActivityDay] = []
    @Published private(set) var following: Set<String> = []
    @Published private(set) var refreshingTab: NotchTab?

    @Published private(set) var findings: [String: [Finding]] = [:]
    @Published private(set) var reviewStep: ReviewStep?
    @Published private(set) var reviewProgress: [ProgressLine] = []
    @Published private(set) var reviewStartedAt: Date?
    @Published private(set) var reviewingKey: String?
    @Published private(set) var maps: [String: PRMap] = [:]
    @Published private(set) var mappingKey: String?

    @Published var settings = Settings() {
        didSet {
            guard settings != oldValue else { return }
            store.saveSettings(settings)
            notifier.settings = settings
            if settings.interval != oldValue.interval { restartTimer() }
        }
    }

    enum NotchTab: String, CaseIterable, Identifiable {
        case queue, team, ranking, activity
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .queue:  "tray.full"
            case .team: "person.2"
            case .ranking:  "trophy"
            case .activity: "square.grid.3x3"
            }
        }
        var title: String {
            switch self {
            case .queue:  "Queue"
            case .team:  "Team"
            case .ranking:  "Rank"
            case .activity: "Rhythm"
            }
        }
    }

    @Published var tab: Tab = .waiting
    @Published var selected: PR?
    @Published private(set) var sending = false

    enum Tab: String, CaseIterable, Identifiable {
        case waiting, mine, reviewing, following
        var id: String { rawValue }
        var title: String {
            switch self {
            case .waiting:  "Needs you"
            case .mine:       "Your PRs"
            case .reviewing:  "Reviewing"
            case .following: "Following"
            }
        }
        var icon: String {
            switch self {
            case .waiting:  "tray.full"
            case .mine:       "arrow.triangle.branch"
            case .reviewing:  "bubble.left.and.bubble.right"
            case .following: "eye"
            }
        }
    }

    var rankPeriod: RankPeriod = .month {
        didSet {
            guard rankPeriod != oldValue else { return }
            ranking = store.state.cache.rank(rankPeriod)
            loadTab(.ranking)
        }
    }

    @Published var repos: [RepoRef] = []
    @Published var selectedRepo: String?
    @Published var repoPRs: [PR] = []
    @Published var loadingRepo = false
    @Published var repoShowsDraft = false
    @Published var watching: Set<String> = []

    enum RepoGroup: Identifiable {
        case personal([RepoRef])
        case org(String, [RepoRef])

        var id: String {
            switch self {
            case .personal:      "~personal"
            case .org(let o, _): o
            }
        }
        var title: String {
            switch self {
            case .personal:      "Personal"
            case .org(let o, _): o
            }
        }
        var items: [RepoRef] {
            switch self {
            case .personal(let r):  r
            case .org(_, let r):    r
            }
        }
    }

    var repoGroups: [RepoGroup] {
        let orgs = Dictionary(grouping: repos.filter(\.isOrg), by: \.owner)
            .map { RepoGroup.org($0.key, $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.title.lowercased() < $1.title.lowercased() }
        let mine = repos.filter { !$0.isOrg }.sorted { $0.name < $1.name }
        return orgs + (mine.isEmpty ? [] : [.personal(mine)])
    }

    var repoPRsShown: [PR] {
        repoPRs.filter { $0.draft == repoShowsDraft }
    }

    func loadRepos(force: Bool = false) {
        let cache = store.state.cache
        if !force, let cached = cache.repos, !cached.isEmpty,
           !cache.isStale(cache.reposAt, after: 24 * 3600) {
            repos = cached
            return
        }
        if let cached = cache.repos { repos = cached }
        Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await client.fetchRepos()
                var c = self.store.state.cache
                c.repos = fetched
                c.reposAt = Date()
                self.store.saveCache(c)
                self.repos = fetched
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func selectRepo(_ full: String?) {
        selectedRepo = full
        repoPRs = []
        guard let full else { return }
        loadingRepo = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.loadingRepo = false }
            do {
                self.repoPRs = try await self.client.fetchRepoPRs(full)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleWatch(_ repo: String) {
        store.toggleWatch(repo)
        watching = store.state.watching ?? []
    }

    private let client = GitHubClient()
    private let store = Store()
    private let notifier = Notifier()
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        notifier.install()
        notifier.onChange = { [weak self] in await self?.refresh() }
        defer { loadRepos() }
        unread = store.state.unread
        following = store.state.following
        watching = store.state.watching ?? []
        let cache = store.state.cache
        team = cache.team
        repos = cache.repos ?? []
        ranking = cache.rank(rankPeriod)
        activity = cache.activity
        settings = store.state.settings
        notifier.settings = settings

        Task {
            hasPermission = await notifier.isAuthorized()
            if !hasPermission { hasPermission = await notifier.requestPermission() }
            await refresh()
        }

        restartTimer()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        do {
            let latest = try await client.fetchQueue()
            let events = store.diff(latest, viewerLogin: latest.viewer)
                .filter { e in
                    let repo = e.key.split(separator: "#").first.map(String.init) ?? ""
                    return !settings.mutedRepos.contains(repo)
                }
            queue = latest
            if let s = selected {
                selected = latest.all.first { $0.key == s.key } ?? s
            }
            unread = store.state.unread
            lastSync = Date()
            errorMessage = nil
            await notifier.post(events)
            onCountChange?()
            if let first = events.first(where: { $0.kind.interrupts }) {
                onEvent?(first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var org: String {
        let owners = queue.all.compactMap { $0.repo.split(separator: "/").first.map(String.init) }
        let count = Dictionary(grouping: owners, by: { $0 }).mapValues(\.count)
        return count.max { $0.value < $1.value }?.key ?? ""
    }

    func toggleFollow(_ login: String) {
        store.toggleFollow(login)
        following = store.state.following
        var cache = store.state.cache
        cache.dropRanks()
        store.saveCache(cache)
        team = cache.team
        activity = cache.activity
        ranking = ranking.filter { rankingScope(cache.team).contains($0.person) }
        loadTab(.ranking, force: true)
    }

    func loadTab(_ tab: NotchTab, force: Bool = false) {
        guard !org.isEmpty else { return }
        guard force || refreshingTab == nil else { return }
        guard tab != .queue else { return }

        let cache = store.state.cache
        let stale: Bool = switch tab {
        case .queue:    false
        case .team:     cache.isStale(cache.teamAt, after: 24 * 3600)
        case .ranking:  cache.isStale(cache.rankAt(rankPeriod), after: rankPeriod.freshFor)
        case .activity: cache.isStale(cache.activityAt, after: 3600)
        }
        guard force || stale else { return }

        refreshingTab = tab
        refreshTask?.cancel()
        _ = ()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshingTab = nil }
            await self.fetchTab(tab)
        }
    }

    private func fetchTab(_ tab: NotchTab) async {
        var cache = store.state.cache
        do {
            if cache.team.isEmpty || cache.isStale(cache.teamAt, after: 24 * 3600) {
                cache.team = try await client.fetchTeam(org: org)
                cache.teamAt = Date()
                team = cache.team
            }
            switch tab {
            case .ranking:
                let period = rankPeriod
                let rows = try await client.fetchRanking(
                    org: org, people: rankingScope(cache.team), from: period.since
                )
                cache.setRank(rows, for: period)
                if period == rankPeriod { ranking = rows }
            case .activity:
                cache.activity = try await client.fetchActivity(org: org, login: queue.viewer)
                cache.activityAt = Date()
                activity = cache.activity
            default: break
            }
            store.saveCache(cache)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var myRank: RankRow? { ranking.first { $0.person.login == queue.viewer } }

    private func rankingScope(_ all: [Person]) -> [Person] {
        let picked = all.filter { following.contains($0.login) || $0.login == queue.viewer }
        return picked.count >= 2 ? picked : Array(all.prefix(20))
    }

    func runAIReview(_ pr: PR) async {
        guard reviewingKey == nil else { return }
        reviewingKey = pr.key
        reviewProgress = []
        reviewStartedAt = Date()
        note("finding the repository")
        defer { reviewingKey = nil }

        guard let origin = Worktree.localPath(pr.repo, configured: settings.repoPaths) else {
            reviewStep = .failed("could not find \(pr.repo) on this machine. Point at the folder in Settings.")
            note("repository not found", closing: true)
            return
        }

        var target: URL?
        do {
            note("fetching the diff base from GitHub")
            let (base, _) = try await client.baseAndModules(repo: pr.repo, pr: pr.number)

            note("preparing the worktree")
            let w = try await Worktree.prepare(
                origin: origin, repo: pr.repo, pr: pr.number, base: base
            )
            target = w

            note("Claude is reading the code")
            for await step in Reviewer().review(
                pr: pr, base: base, in: w, model: settings.aiModel,
                language: settings.reviewLanguage
            ) {
                reviewStep = step
                switch step {
                case .preparing(let t), .tool(let t): note(t)
                case .thinking: note("thinking")
                case .done(let list):
                    findings[pr.key] = list
                    note("\(list.count) finding\(list.count == 1 ? "" : "s")",
                           closing: true)
                case .failed(let m): note(m, closing: true)
                }
            }
        } catch {
            reviewStep = .failed(error.localizedDescription)
            note(error.localizedDescription, closing: true)
        }

        _ = target
    }

    private func note(_ text: String, closing: Bool = false) {
        if var last = reviewProgress.last, last.text == text {
            last.repeats += 1
            reviewProgress[reviewProgress.count - 1] = last
            return
        }
        if !reviewProgress.isEmpty { reviewProgress[reviewProgress.count - 1].done = true }
        reviewProgress.append(ProgressLine(text: text, done: closing))
        if reviewProgress.count > 14 { reviewProgress.removeFirst() }
    }

    func buildMap(_ pr: PR) async {
        guard mappingKey == nil else { return }
        mappingKey = pr.key
        defer { mappingKey = nil }

        guard let origin = Worktree.localPath(pr.repo, configured: settings.repoPaths) else {
            errorMessage = "could not find \(pr.repo) on this machine. Point at the folder in Settings."
            return
        }

        var target: URL?
        do {
            let (base, changed) = try await client.baseAndModules(repo: pr.repo, pr: pr.number)
            let w = try await Worktree.prepare(
                origin: origin, repo: pr.repo, pr: pr.number, base: base
            )
            target = w

            if let m = await MapBuilder().build(
                pr: pr, base: base, changed: changed, in: w, model: settings.aiModel,
                language: settings.reviewLanguage
            ) {
                maps[pr.key] = m
            } else {
                maps[pr.key] = PRMap(
                    intent: pr.title,
                    deltas: [],
                    changed: changed,
                    affected: [],
                    context: []
                )
                errorMessage = "the map only has what the diff gives; the session did not answer in JSON"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        if let d = target { await Worktree.discard(origin: origin, target: d) }
    }

    func sendTestEvent(_ kind: EventKind) async {
        let pr = queue.all.first
        let event = Event(
            id: "test/\(kind.rawValue)/\(Date().timeIntervalSince1970)",
            kind: kind,
            key: pr?.key ?? "example#1",
            url: pr?.url ?? URL(string: "https://github.com")!,
            title: testText(kind).0,
            body: pr.map { "\($0.key) · \($0.title)" } ?? testText(kind).1
        )
        onEvent?(event)
        await notifier.post([event], force: true)
    }

    var isQuietNow: Bool {
        guard settings.quietHoursOn else { return false }
        return !settings.shouldInterrupt(.commented)
    }

    private func testText(_ t: EventKind) -> (String, String) {
        switch t {
        case .repliedToYou: ("Marina replied to you", "resend.ts:214 · what if the ticket already expired?")
        case .commented:      ("Ana commented on your PR", "send.ts:58 · this swallows the 429 silently")
        case .reviewRequested:   ("Rafael requested your review", "4 files · +94 −12")
        case .checkFailed:     ("A check failed on your PR", "ci / test · 1 of 5 failing")
        case .approved:       ("Your PR was approved", "ready to merge")
        }
    }

    func discardFinding(_ pr: PR, _ a: Finding) {
        findings[pr.key]?.removeAll { $0.id == a.id }
    }

    func open(_ pr: PR) {
        NSWorkspace.shared.open(pr.url)
        store.markRead(pr.key)
        unread = store.state.unread
    }

    func clearAll() {
        store.markAllRead()
        unread = store.state.unread
    }

    enum NeedsReason: Sendable {
        case reviewRequested
        case replied

        var label: String {
            switch self {
            case .reviewRequested: "review requested"
            case .replied:         "replied to you"
            }
        }
    }

    func needsReason(_ pr: PR) -> NeedsReason? {
        if unread.contains(pr.key) { return .replied }
        if queue.toReview.contains(where: { $0.key == pr.key }) { return .reviewRequested }
        return nil
    }

    var needsYou: [PR] {
        var seen = Set<String>()
        var out: [PR] = []
        for pr in queue.toReview + queue.all.filter({ unread.contains($0.key) }) {
            guard pr.author != queue.viewer || unread.contains(pr.key) else { continue }
            if seen.insert(pr.key).inserted { out.append(pr) }
        }
        return out
    }

    var yoursBroken: [PR] { queue.mine.filter { $0.checks == .failing } }

    var count: Int { needsYou.count }

    func prs(_ tab: Tab) -> [PR] {
        switch tab {
        case .waiting:  needsYou
        case .mine:       queue.mine
        case .reviewing:  queue.toReview
        case .following: queue.following
        }
    }

    func count(_ tab: Tab) -> Int { prs(tab).count }

    func reply(thread: String, text: String) async -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        sending = true
        defer { sending = false }
        do {
            try await client.reply(threadId: thread, body: t)
            await refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func resolve(thread: String) async -> String? {
        sending = true
        defer { sending = false }
        do {
            try await client.resolve(threadId: thread)
            await refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var rest: [PR] {
        let urgent = Set(needsYou.map(\.key))
        return queue.mine.filter { !urgent.contains($0.key) }
    }
}
