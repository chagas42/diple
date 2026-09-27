import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {
    static let compartilhado = AppModel()

    var onEvent: ((Event) -> Void)?
    var onCountChange: (() -> Void)?

    @Published private(set) var queue = Queue()
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var hasPermission = false
    @Published private(set) var unread: Set<String> = []

    @Published var abaNotch: NotchTab = .queue
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

    @Published var tab: Tab = .esperando
    @Published var selected: PR?
    @Published private(set) var sending = false

    enum Tab: String, CaseIterable, Identifiable {
        case esperando, mine, revisando, observando
        var id: String { rawValue }
        var title: String {
            switch self {
            case .esperando:  "Needs you"
            case .mine:       "Your PRs"
            case .revisando:  "Reviewing"
            case .observando: "Following"
            }
        }
        var icon: String {
            switch self {
            case .esperando:  "tray.full"
            case .mine:       "arrow.triangle.branch"
            case .revisando:  "bubble.left.and.bubble.right"
            case .observando: "eye"
            }
        }
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
        unread = store.state.unread
        following = store.state.following
        let cache = store.state.cache
        team = cache.team
        ranking = cache.ranking
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
        let cache = store.state.cache
        team = cache.team
        ranking = cache.ranking
        activity = cache.activity
    }

    func loadTab(_ tab: NotchTab) {
        guard !org.isEmpty, refreshingTab == nil else { return }

        guard tab != .queue else { return }
        let cache = store.state.cache
        let stale: Bool = switch tab {
        case .queue:    false
        case .team:     cache.isStale(cache.teamAt, after: 24 * 3600)
        case .ranking:  cache.isStale(cache.rankingAt, after: 6 * 3600)
        case .activity: cache.isStale(cache.activityAt, after: 3600)
        }
        guard stale else { return }

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
                let from = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
                cache.ranking = try await client.fetchRanking(
                    org: org, people: rankingScope(cache.team), from: from
                )
                cache.rankingAt = Date()
                ranking = cache.ranking
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

    var shouldAnimateScore: Bool {
        guard let shown = store.state.cache.scoreShownOn else { return true }
        return !Calendar.current.isDateInToday(shown)
    }

    func markScoreShown() {
        var cache = store.state.cache
        cache.scoreShownOn = Date()
        store.saveCache(cache)
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
            reviewStep = .failing("could not find \(pr.repo) on this machine. Point at the folder in Settings.")
            note("repository not found", fechando: true)
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
            for await passo in Reviewer().review(
                pr: pr, base: base, in: w, model: settings.aiModel,
                language: settings.reviewLanguage
            ) {
                reviewStep = passo
                switch passo {
                case .preparando(let t), .ferramenta(let t): note(t)
                case .pensando: note("thinking")
                case .pronto(let list):
                    findings[pr.key] = list
                    note("\(list.count) apontamento\(list.count == 1 ? "" : "s")",
                           fechando: true)
                case .failing(let m): note(m, fechando: true)
                }
            }
        } catch {
            reviewStep = .failing(error.localizedDescription)
            note(error.localizedDescription, fechando: true)
        }

        _ = target
    }

    private func note(_ text: String, fechando: Bool = false) {
        if var last = reviewProgress.last, last.text == text {
            last.repeats += 1
            reviewProgress[reviewProgress.count - 1] = last
            return
        }
        if !reviewProgress.isEmpty { reviewProgress[reviewProgress.count - 1].done = true }
        reviewProgress.append(ProgressLine(text: text, done: fechando))
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
        let evento = Event(
            id: "teste/\(kind.rawValue)/\(Date().timeIntervalSince1970)",
            kind: kind,
            key: pr?.key ?? "exemplo#1",
            url: pr?.url ?? URL(string: "https://github.com")!,
            title: testText(kind).0,
            body: pr.map { "\($0.key) · \($0.title)" } ?? testText(kind).1
        )
        onEvent?(evento)
        await notificador.post([evento], force: true)
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

    var needsYou: [PR] {
        var vistos = Set<String>()
        var out: [PR] = []
        for pr in queue.toReview + queue.mine.filter({ $0.checks == .failing })
                 + queue.all.filter({ unread.contains($0.key) }) {
            if vistos.insert(pr.key).inserted { out.append(pr) }
        }
        return out
    }

    var count: Int { needsYou.count }

    func prs(_ tab: Tab) -> [PR] {
        switch tab {
        case .esperando:  needsYou
        case .mine:       queue.mine
        case .revisando:  queue.toReview
        case .observando: queue.following
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
