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

    @Published private(set) var reviewResults: [String: ReviewResult] = [:]
    @Published private(set) var reviewContexts: [String: ReviewContext] = [:]
    struct ReviewRun: Sendable {
        var step: ReviewStep?
        var progress: [ProgressLine] = []
        var startedAt: Date?
    }

    @Published private(set) var runs: [String: ReviewRun] = [:]

    func run(_ key: String) -> ReviewRun? { runs[key] }
    func isReviewing(_ key: String) -> Bool { runs[key]?.step != nil && !finished(key) }

    private func finished(_ key: String) -> Bool {
        switch runs[key]?.step {
        case .done, .failed, .none: true
        default:                    false
        }
    }
    @Published private(set) var maps: [String: PRMap] = [:]
    @Published private(set) var mappingKey: String?
    @Published private(set) var mapRun: MapRun?
    @Published private(set) var mapRunKeys: Set<String> = []
    @Published private(set) var mapNotice: String?
    @Published private(set) var mapLayouts: [String: [String: CGPoint]] = [:]
    private var mapRoots: [String: [URL]] = [:]

    @Published var settings = Settings() {
        didSet {
            guard settings != oldValue else { return }
            store.saveSettings(settings)
            notificador.settings = settings
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
            case .activity: "Ritmo"
            }
        }
    }

    @Published var tab: Tab = .needsYou
    @Published var selected: PR?
    @Published private(set) var sending = false

    enum Tab: String, CaseIterable, Identifiable {
        case needsYou, mine, reviewing, following
        var id: String { rawValue }
        var title: String {
            switch self {
            case .needsYou:  "Needs you"
            case .mine:       "Your PRs"
            case .reviewing:  "Reviewing"
            case .following: "Following"
            }
        }
        var icon: String {
            switch self {
            case .needsYou:  "tray.full"
            case .mine:       "arrow.triangle.branch"
            case .reviewing:  "bubble.left.and.bubble.right"
            case .following: "eye"
            }
        }
    }

    var rankPeriod: RankPeriod = .month {
        didSet {
            guard rankPeriod != oldValue else { return }
            ranking = Demo.isOn ? Demo.ranking(rankPeriod) : store.state.cache.rank(rankPeriod)
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
        if Demo.isOn {
            repos = Demo.team.isEmpty ? [] : [
                RepoRef(nameWithOwner: "acme/orders-api", owner: "acme", isOrg: true, isPrivate: true),
                RepoRef(nameWithOwner: "acme/console", owner: "acme", isOrg: true, isPrivate: true),
                RepoRef(nameWithOwner: "acme/notifier", owner: "acme", isOrg: true, isPrivate: true),
                RepoRef(nameWithOwner: "acme/mobile", owner: "acme", isOrg: true, isPrivate: true),
                RepoRef(nameWithOwner: "acme/warehouse", owner: "acme", isOrg: true, isPrivate: true),
                RepoRef(nameWithOwner: "chagas42/diple", owner: "you", isOrg: false, isPrivate: true),
                RepoRef(nameWithOwner: "chagas42/jsonl-inspect", owner: "you", isOrg: false, isPrivate: false),
            ]
            watching = ["acme/orders-api"]
            return
        }
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
        if Demo.isOn {
            repoPRs = Demo.queue.all.filter { $0.repo == full }
            loadingRepo = false
            return
        }
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

    @Published private(set) var posting: Set<UUID> = []
    @Published private(set) var posted: Set<UUID> = []

    func postOnGitHub(_ finding: Finding, on pr: PR) async {
        guard !posting.contains(finding.id), !posted.contains(finding.id) else { return }
        posting.insert(finding.id)
        defer { posting.remove(finding.id) }
        do {
            try await client.startThread(
                prId: pr.id, path: finding.path, line: finding.line,
                body: signed(finding.comment ?? finding.summary, on: pr)
            )
            posted.insert(finding.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signed(_ body: String, on pr: PR) -> String {
        guard settings.attributionMode.applies(mine: pr.isMine) else { return body }
        return body + "\n\n<sub>via [Diple](https://github.com/chagas42/diple) — drafted by a Claude review running locally</sub>"
    }

    func reportOpenFailure(_ message: String) { errorMessage = message }

    func toggleWatch(_ repo: String) {
        store.toggleWatch(repo)
        watching = store.state.watching ?? []
    }

    private let client = GitHubClient()
    private let store = Store()
    private let notificador = Notifier()
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        notificador.install()
        notificador.onChange = { [weak self] in await self?.refresh() }
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
        notificador.settings = settings

        Task {
            hasPermission = await notificador.isAuthorized()
            if !hasPermission { hasPermission = await notificador.requestPermission() }
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
        if Demo.isOn {
            queue = Demo.queue
            unread = Demo.unread
            team = Demo.team
            ranking = Demo.ranking(rankPeriod)
            activity = Demo.activity
            lastSync = Date()
            errorMessage = nil
            onCountChange?()
            return
        }
        guard !loading else { return }
        loading = true
        defer { loading = false }

        do {
            let nova = try await client.fetchQueue()
            let events = store.diff(nova, meuLogin: nova.viewer)
                .filter { e in
                    let repo = e.key.split(separator: "#").first.map(String.init) ?? ""
                    return !settings.mutedRepos.contains(repo)
                }
            queue = nova
            if let s = selected {
                selected = nova.all.first { $0.key == s.key } ?? s
            }
            unread = store.state.unread
            lastSync = Date()
            errorMessage = nil
            await notificador.post(events)
            onCountChange?()
            if let first = events.first(where: { $0.kind.interrupts }) {
                onEvent?(first)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var org: String {
        let donos = queue.all.compactMap { $0.repo.split(separator: "/").first.map(String.init) }
        let count = Dictionary(grouping: donos, by: { $0 }).mapValues(\.count)
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
        if Demo.isOn {
            team = Demo.team
            ranking = Demo.ranking(rankPeriod)
            activity = Demo.activity
            return
        }
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
        guard !isReviewing(pr.key) else { return }
        runs[pr.key] = ReviewRun(step: .preparing("starting"), startedAt: Date())
        note(pr.key, "finding the repository")

        guard let origin = Worktree.localPath(pr.repo, configured: settings.repoPaths) else {
            runs[pr.key]?.step = .failed("could not find \(pr.repo) on this machine. Point at the folder in Settings.")
            note(pr.key, "repository not found", fechando: true)
            return
        }

        var target: URL?
        do {
            note(pr.key, "reading the PR, its threads and comments from GitHub")
            let context = try await client.reviewContext(repo: pr.repo, pr: pr.number)

            note(pr.key, "preparing the worktree")
            let w = try await Worktree.prepare(
                origin: origin, repo: pr.repo, pr: pr.number, base: context.base
            )
            target = w

            note(pr.key, DeepReview.available
                 ? "deep review: two axes, the value pass, then \(context.openThreads) open thread\(context.openThreads == 1 ? "" : "s")"
                 : "Claude is reading the code")
            for await step in Reviewer().review(
                pr: pr, context: context, viewer: queue.viewer,
                in: w, model: settings.aiModel, language: settings.reviewLanguage
            ) {
                runs[pr.key]?.step = step
                switch step {
                case .preparing(let t), .tool(let t): note(pr.key, t)
                case .thinking: note(pr.key, "thinking")
                case .done(let r):
                    reviewContexts[pr.key] = context
                    reviewResults[pr.key] = r
                    let judged = r.threads.isEmpty ? "" : " · \(r.threads.count) thread\(r.threads.count == 1 ? "" : "s") judged"
                    note(pr.key, "\(r.novel.count) finding\(r.novel.count == 1 ? "" : "s")\(judged)", fechando: true)
                case .failed(let m): note(pr.key, m, fechando: true)
                }
            }
        } catch {
            runs[pr.key]?.step = .failed(error.localizedDescription)
            note(pr.key, error.localizedDescription, fechando: true)
        }

        _ = target
    }

    private func note(_ key: String, _ text: String, fechando: Bool = false) {
        var r = runs[key] ?? ReviewRun()
        if var last = r.progress.last, last.text == text {
            last.repeats += 1
            r.progress[r.progress.count - 1] = last
            runs[key] = r
            return
        }
        if !r.progress.isEmpty { r.progress[r.progress.count - 1].done = true }
        r.progress.append(ProgressLine(text: text, done: fechando))
        if r.progress.count > 14 { r.progress.removeFirst() }
        runs[key] = r
    }

    func stackOf(_ pr: PR) -> [PR] {
        queue.all.groupedIntoStacks().first { s in s.prs.contains { $0.key == pr.key } }?.prs ?? [pr]
    }

    func buildMap(_ pr: PR) async {
        guard mappingKey == nil else { return }
        let prs = stackOf(pr)
        let keys = Set(prs.map(\.key))
        let started = Date()
        mappingKey = pr.key
        mapRunKeys = keys
        mapNotice = nil
        mapRun = MapRun(
            phase: "reading the diff",
            startedAt: started,
            estimate: MapTiming.estimate(size: MapSize(), worktreeReady: true),
            expectedTools: 6
        )
        defer {
            mappingKey = nil
            mapRun = nil
            mapRunKeys = []
        }

        var map: PRMap
        var changedPaths = Set<String>()
        do {
            let scans = try await withThrowingTaskGroup(of: PRFiles.self) { group in
                for p in prs {
                    group.addTask { [client] in try await client.changedFiles(repo: p.repo, pr: p.number) }
                }
                var all: [PRFiles] = []
                for try await s in group { all.append(s) }
                let order = prs.map(\.number)
                return all.sorted { (order.firstIndex(of: $0.number) ?? 0) < (order.firstIndex(of: $1.number) ?? 0) }
            }
            map = MapScan.build(repo: pr.repo, prs: scans)
            changedPaths = Set(scans.flatMap { $0.files.map(\.path) })
        } catch {
            mapNotice = "could not read the diff: \(error.localizedDescription)"
            return
        }
        for k in keys { maps[k] = map }

        guard let origin = Worktree.localPath(pr.repo, configured: settings.repoPaths) else {
            mapNotice = "only the diff layer: \(pr.repo) is not on this machine. Point at the folder in Settings."
            return
        }
        mapRoots[map.layoutKey] = [origin]

        let top = prs.last ?? pr
        let estimate = MapTiming.estimate(
            size: map.size,
            worktreeReady: Worktree.existing(repo: pr.repo, pr: top.number) != nil
        )
        mapRun = MapRun(
            phase: "preparing the worktree",
            startedAt: started,
            estimate: estimate,
            expectedTools: MapTiming.expectedTools(map.size)
        )

        do {
            let w = try await Worktree.prepare(origin: origin, repo: pr.repo, pr: top.number, base: map.base)
            mapRoots[map.layoutKey] = [w, origin]

            let titles = Dictionary(prs.map { ($0.number, $0.title) }, uniquingKeysWith: { f, _ in f })
            mapRun?.phase = "finding who depends on the change"
            let candidates = await Dependents.find(
                changed: changedPaths,
                modules: Set(map.nodes(.changed).map(\.id)),
                in: w
            )
            mapRun?.phase = "Claude is reading the code"
            var answered = false
            for await step in MapBuilder().enrich(
                map: map, titles: titles, candidates: candidates,
                in: w, model: settings.mapAIModel, language: settings.reviewLanguage
            ) {
                switch step {
                case .session(let s):
                    mapRun?.phase = s
                case .tool(let t):
                    mapRun?.toolCalls += 1
                    mapRun?.lastTool = t
                    mapRun?.phase = "Claude is reading the code"
                case .thinking:
                    break
                case .done(let answer):
                    if let a = answer {
                        answered = true
                        let fm = FileManager.default
                        map = map.merged(a) { fm.fileExists(atPath: w.appendingPathComponent($0).path) }
                        for k in keys { maps[k] = map }
                    } else {
                        mapNotice = "only the diff layer: the session did not answer in the map's JSON"
                    }
                case .failed(let m):
                    mapNotice = "only the diff layer: \(m)"
                }
            }
            if answered {
                MapTiming.record(raw: estimate.raw, actual: Date().timeIntervalSince(started), size: map.size)
            }
        } catch {
            mapNotice = "only the diff layer: \(error.localizedDescription)"
        }
    }

    func saveLayout(_ positions: [String: CGPoint], for map: PRMap) {
        mapLayouts[map.layoutKey] = positions
    }

    func openNode(_ node: MapNode, in map: PRMap, forceWeb: Bool) {
        let fallback = Worktree.localPath(map.repo, configured: settings.repoPaths).map { [$0] } ?? []
        if let message = Opener.open(
            node, in: map, editor: settings.openIn,
            roots: mapRoots[map.layoutKey] ?? fallback, forceWeb: forceWeb
        ) {
            mapNotice = message
        }
    }

    func sendTestEvent(_ kind: EventKind) async {
        let pr = queue.all.first
        let event = Event(
            id: "teste/\(kind.rawValue)/\(Date().timeIntervalSince1970)",
            kind: kind,
            key: pr?.key ?? "exemplo#1",
            url: pr?.url ?? URL(string: "https://github.com")!,
            title: testText(kind).0,
            body: pr.map { "\($0.key) · \($0.title)" } ?? testText(kind).1
        )
        onEvent?(event)
        await notificador.post([event], force: true)
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
        case .checkFailed:     ("A check failed on your PR", "checks / test · 1 de 5 failing")
        case .approved:       ("Your PR was approved", "ready to merge")
        }
    }

    func discardFinding(_ pr: PR, _ a: Finding) {
        reviewResults[pr.key]?.findings.removeAll { $0.id == a.id }
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
        case .needsYou:  needsYou
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
        let urgentes = Set(needsYou.map(\.key))
        return queue.mine.filter { !urgentes.contains($0.key) }
    }
}
