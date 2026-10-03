import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {
    static let shared = Demo.isOn
        ? AppModel(store: Demo.store(), answer: Demo.answer)
        : AppModel()

    var onEvent: ((Event) -> Void)?
    var onCountChange: (() -> Void)?

    @Published private(set) var queue = Queue()
    var loading: Bool { queueObserver?.isFetching ?? false }
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var hasPermission = false
    @Published private(set) var unread: Set<String> = []
    @Published private(set) var reviewedAhead: Set<String> = []

    @Published var notchTab: NotchTab = .queue
    @Published private(set) var following: Set<String> = []

    var team: [Person] {
        return teamObserver?.data ?? teamQuery.flatMap { queries.peek($0) } ?? []
    }

    var ranking: [RankRow] {
        let rows = rankingObserver?.data ?? rankingQuery.flatMap { queries.peek($0) } ?? []
        let people = Dictionary(team.map { ($0.login, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.map { RankRow(person: people[$0.person.login] ?? $0.person, reviews: $0.reviews) }
    }

    var activity: [ActivityDay] {
        return (activityObserver?.data ?? activityQuery.flatMap { queries.peek($0) })?.days ?? []
    }

    var refreshingTab: NotchTab? {
        guard let tab = shownTab else { return nil }
        let fetching = switch tab {
        case .queue:    false
        case .team:     teamObserver?.isFetching == true
        case .ranking:
            settings.rankingMode == .pace
                ? activityObserver?.isFetching == true
                : rankingObserver?.isFetching ?? (teamObserver?.isFetching == true)
        case .activity: activityObserver?.isFetching == true
        }
        return fetching ? tab : nil
    }

    private var shownTab: NotchTab?
    private var reposShown = 0
    private var syncingScreens = false
    private var teamObserver: QueryObserver<[Person]>?
    private var rankingObserver: QueryObserver<[RankRow]>?
    private var activityObserver: QueryObserver<ActivityLog>?

    struct AIReview: Sendable {
        var result: ReviewResult
        var context: ReviewContext
    }

    func aiReview(_ pr: PR) -> AIReview? { queries.cached(reviewKey(pr)) }

    func map(_ pr: PR) -> PRMap? { queries.cached(mapKey(stackOf(pr))) }

    func resultIDs(_ pr: PR) -> [String] { [reviewKey(pr).id, mapKey(stackOf(pr)).id] }

    func holdResults(for pr: PR) async {
        let holds = [reviewKey(pr), mapKey(stackOf(pr))].map(queries.hold)
        try? await Task.sleep(for: .seconds(365 * 24 * 3600))
        withExtendedLifetime(holds) {}
    }

    private func reviewKey(_ pr: PR) -> QueryKey { .aiReview(pr: pr.key, revision: pr.revision) }

    private func mapKey(_ stack: [PR]) -> QueryKey {
        .map(stack: stack.map(\.key).joined(separator: "+"), revisions: stack.map(\.revision).joined(separator: "+"))
    }

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
    @Published private(set) var mapRuns: [String: MapRun] = [:]
    @Published private(set) var mapNotices: [String: String] = [:]
    @Published private(set) var mapLayouts: [String: [String: CGPoint]] = [:]
    private var mapRoots: [String: [URL]] = [:]
    private var sections: [String: DetailView.Section] = [:]

    func section(for key: String) -> DetailView.Section { sections[key] ?? .conversation }
    func remember(_ section: DetailView.Section, for key: String) { sections[key] = section }

    func mapRun(_ key: String) -> MapRun? { mapRuns[key] }
    func isMapping(_ key: String) -> Bool { mapRuns[key] != nil }
    func mapNotice(_ key: String) -> String? { mapNotices[key] }

    @Published var settings = Settings() {
        didSet {
            if settings.rankingMode != oldValue.rankingMode { rankingModeChanged() }
            guard settings != oldValue else { return }
            store.saveSettings(settings)
            notificador.settings = settings
            focus.follows = settings.followsFocus
            if settings.shareUsage != oldValue.shareUsage { telemetry.setConsent(settings.shareUsage) }
            if settings.interval != oldValue.interval { restartTimer() }
            MenuBarItems.measuring = settings.fitsMenuBar
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
        var feedbackFeature: FeedbackFeature {
            switch self {
            case .queue:    .queue
            case .team:     .team
            case .ranking:  .ranking
            case .activity: .activity
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
    @Published private(set) var markingReady: Set<String> = []

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
            objectWillChange.send()
            syncScreens()
        }
    }

    @Published private(set) var selectedRepo: String?
    private var reposObserver: QueryObserver<[RepoRef]>?
    private var repoObserver: QueryObserver<[PR]>?

    var repos: [RepoRef] { reposObserver?.data ?? queries.peek(reposQuery) ?? [] }

    var repoPRs: [PR] { repoObserver?.data ?? [] }

    var loadingRepo: Bool { repoObserver?.isFetching ?? false }
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

    func loadRepos() {
        queries.prefetch(reposQuery)
    }

    func showRepos() async {
        loadRepos()
        reposShown += 1
        syncScreens()
        try? await Task.sleep(for: .seconds(365 * 24 * 3600))
        reposShown -= 1
        syncScreens()
    }

    private var reposQuery: CacheQuery<[RepoRef]> { reporting(Queries.repos, in: .loadRepos) }

    private func repoQuery(_ repo: String) -> CacheQuery<[PR]> {
        var q = Queries.repoPRs(repo)
        q.retryDelays = Queries.networkRetries
        return q.onError { [weak self] error in
            guard let self, self.selectedRepo == repo, let m = self.report(error, in: .repoPRs) else { return }
            self.errorMessage = m
        }
    }

    func selectRepo(_ full: String?) {
        selectedRepo = full
        syncScreens()
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
            telemetry.capture(.findingPosted)
            await reread(pr)
        } catch {
            if let m = report(error, in: .postFinding) { errorMessage = m }
        }
    }

    func signed(_ body: String, on pr: PR) -> String {
        guard settings.attributionMode.applies(mine: pr.isMine) else { return body }
        return body + "\n\n<sub>via [Diple](https://github.com/chagas42/diple) — drafted by a Claude review running locally</sub>"
    }

    func reread(_ pr: PR) async {
        guard let fresh = try? await client.fetchPR(repo: pr.repo, number: pr.number) else {
            await refresh()
            return
        }
        put(fresh)
        if queries.isFetching(.queue(watching: watching)) { queries.invalidate(.queue) }
        if queries.isFetching(.repoPRs(repo: fresh.repo)) { queries.invalidate(.repo(fresh.repo)) }
        queries.invalidate(.pr(fresh.key))
    }

    private func put(_ fresh: PR) {
        func swap(_ list: [PR]) -> [PR] { list.map { $0.key == fresh.key ? fresh : $0 } }
        func swap(_ q: inout Queue) {
            q.mine = swap(q.mine)
            q.toReview = swap(q.toReview)
            q.following = swap(q.following)
        }
        swap(&queue)
        queries.setData(.queue(watching: watching)) { (o: inout SyncOutcome) in swap(&o.queue) }
        if selected?.key == fresh.key { selected = fresh }
        queries.setData(.repoPRs(repo: fresh.repo)) { (prs: inout [PR]) in prs = swap(prs) }
    }

    func canMarkReady(_ pr: PR) -> Bool { pr.isMine && pr.draft }

    func markReady(_ pr: PR) async -> String? {
        guard canMarkReady(pr), !markingReady.contains(pr.key) else { return nil }
        markingReady.insert(pr.key)
        defer { markingReady.remove(pr.key) }
        var ready = pr
        ready.draft = false
        put(ready)
        guard !queries.answersLocally else { return nil }
        do {
            try await client.markReadyForReview(prId: pr.id)
            await reread(ready)
            return nil
        } catch {
            var draft = queue.all.first { $0.key == pr.key } ?? pr
            draft.draft = true
            put(draft)
            report(error, in: .markReady)
            return ReadyForReview.explain(error)
        }
    }

    func reportOpenFailure(_ message: String) { errorMessage = message }

    var syncProblem: String? {
        guard isOnline else {
            guard let last = lastSync else { return "Offline" }
            return "Offline · showing the queue from \(last.formatted(date: .omitted, time: .shortened))"
        }
        return errorMessage
    }

    @discardableResult
    func report(_ error: Error, in operation: ErrorReport.Operation) -> String? {
        let context = ErrorReport.Context(
            network: network,
            failuresInRow: failures + partialFailures,
            sinceLastSync: .init(lastSync)
        )
        let r = ErrorReport(error, in: operation, context: context)
        ErrorReport.log(error, in: operation, report: r)
        guard let r else { return nil }
        telemetry.capture(.error(r))
        return error.localizedDescription
    }

    func toggleWatch(_ repo: String) {
        store.toggleWatch(repo)
        watching = store.state.watching ?? []
        guard lastSync != nil, canFetch else { return }
        bindQueue()
    }

    private let client: GitHubClient
    private let store: Store
    private let notificador = Notifier()
    let focus = Focus()

    private let sync: SyncEngine
    let telemetry: Telemetry
    @Published private(set) var usageNoticeVisible = false
    private var pendingSeed: Queue?
    let prefetcher: Prefetcher
    let queries: QueryClient
    private var prefetchTask: Task<Void, Never>?
    var preloadsTabs = true

    init(
        client: GitHubClient = GitHubClient(),
        store: Store = Store(),
        fetchRefs: Prefetcher.FetchRefs? = nil,
        telemetry: Telemetry = .shared,
        answer: QueryClient.Answer? = nil
    ) {
        self.telemetry = telemetry
        self.notificador.telemetry = telemetry
        self.client = client
        self.store = store
        let queries = QueryClient(github: client, store: store, decoders: Queries.savedDecoders, answer: answer)
        self.queries = queries
        self.sync = SyncEngine(client: client)
        self.prefetcher = fetchRefs.map { Prefetcher(queries: queries, fetchRefs: $0) } ?? Prefetcher(queries: queries)
        queries.onChange = { [weak self] in
            self?.objectWillChange.send()
            self?.syncScreens()
        }
    }

    func reviewContext(for pr: PR) async throws -> ReviewContext {
        try await queries.fetch(Queries.reviewContext(pr))
    }

    func prefetchTargets() -> [Prefetcher.Target] {
        needsYou.prefix(Prefetcher.depth).map {
            Prefetcher.Target(pr: $0, origin: Worktree.localPath($0.repo, configured: settings.repoPaths))
        }
    }

    func prefetchSettled() async {
        await prefetchTask?.value
    }

    func tabsSettled() async {
        await queries.settle()
    }

    private func schedulePreload() {
        guard preloadsTabs, !Bench.isOn, canFetch else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled, let teamQuery else { return }
        queries.prefetch(teamQuery) { [weak self] team in
            self?.settings.rankingMode == .team ? self?.rankingQuery(for: team) : nil
        }
        if let activityQuery { queries.prefetch(activityQuery) }
    }

    private func schedulePrefetch() {
        guard !queries.answersLocally, !Bench.isOn, isOnline, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        guard prefetchTask == nil else { return }
        let targets = prefetchTargets()
        guard !targets.isEmpty else { return }
        prefetchTask = Task(priority: .utility) { [weak self, prefetcher] in
            await prefetcher.warm(targets)
            self?.prefetchTask = nil
        }
    }
    private var pollTask: Task<Void, Never>?
    private let reachability = Reachability()
    private(set) var network = NetworkState()
    @Published var isOnline = true
    private(set) var failures = 0
    private(set) var partialFailures = 0
    private var queueObserver: QueryObserver<SyncOutcome>?

    private var canFetch: Bool { isOnline || queries.answersLocally }
    private var notchOpen = false

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        notificador.install()
        notificador.onChange = { [weak self] in await self?.refresh() }
        restoreCached()
        settings = store.state.settings
        notificador.settings = settings
        MenuBarItems.measuring = settings.fitsMenuBar
        notificador.quiet = { [weak self] in self?.focus.isOn ?? false }
        focus.follows = settings.followsFocus
        focus.start()
        startTelemetry()
        Updates.shared.start()

        Task {
            await refresh()
            loadRepos()
        }
        Task {
            hasPermission = await notificador.isAuthorized()
            if !hasPermission { hasPermission = await notificador.requestPermission() }
        }

        restartTimer()
        reachability.onChange = { [weak self] state in
            self?.network = state
            self?.setOnline(state.online)
        }
        reachability.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refetchShown()
                await self?.refresh(full: true)
            }
        }
    }

    func startTelemetry() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        telemetry.configure(
            installId: store.ensureInstallId(),
            consent: settings.shareUsage,
            common: [
                "app_version": .text(version),
                "os_version": .text("\(os.majorVersion).\(os.minorVersion)"),
                "has_notch": .bool(NotchGeometry.current().hasNotch),
            ]
        )
        usageNoticeVisible = telemetry.isActive && !store.state.usageNoticeSeen
    }

    func recordActiveDay(now: Date = Date()) {
        guard telemetry.isActive else { return }
        let day = now.formatted(.iso8601.year().month().day())
        guard store.markActive(on: day) else { return }
        telemetry.capture(.appActive(needsYou: needsYou.count, mine: queue.mine.count, toReview: queue.toReview.count))
    }

    var canSendQuickFeedback: Bool { telemetry.isActive }

    func sendQuickFeedback(feature: FeedbackFeature, rating: TelemetryEvent.Rating?, text: String) {
        telemetry.capture(.feedbackSubmitted(feature: feature, rating: rating, text: text))
        let telemetry = self.telemetry
        Task.detached(priority: .utility) { await telemetry.flush() }
    }

    func issueURL(title: String, description: String, feature: FeedbackFeature, diagnostics: Bool) -> URL {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let block = diagnostics ? FeedbackText.diagnostics(
            feature: feature, version: version,
            os: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            machine: Self.machineModel
        ) : nil
        return FeedbackText.issueURL(title: title, description: description, feature: feature, diagnostics: block)
    }

    func openIssue(title: String, description: String, feature: FeedbackFeature, diagnostics: Bool) {
        openURL(issueURL(title: title, description: description, feature: feature, diagnostics: diagnostics))
    }

    static let machineModel: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }()

    func dismissUsageNotice() {
        store.markUsageNoticeSeen()
        usageNoticeVisible = false
    }

    func resetAnonymousId() {
        telemetry.setInstallId(store.resetInstallId())
    }

    var anonymousId: String { store.state.installId ?? "" }

    func restoreCached() {
        unread = store.state.unread
        following = store.state.following
        watching = store.state.watching ?? []
        if let cached = store.state.cache.queue, queue.all.isEmpty {
            queue = cached
            pendingSeed = cached
            onCountChange?()
        }
    }

    var policy: SyncPolicy {
        SyncPolicy(
            base: settings.interval,
            failures: failures,
            partialFailures: partialFailures,
            online: isOnline,
            visible: notchOpen || Windows.shared.mainIsVisible,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            rateLimitLeft: lastSync == nil ? nil : queue.rateLimitLeft,
            rateLimitResetAt: queue.rateLimitResetAt
        )
    }

    private func restartTimer() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let policy = self?.policy else { return }
                let delay = policy.nextDelay() ?? 60
                try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(delay * 0.1))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func setNotchOpen(_ open: Bool) {
        guard open != notchOpen else { return }
        notchOpen = open
        shownTab = open && notchTab != .queue ? notchTab : nil
        syncScreens()
        if open { refetchShown() }
        if open, let last = lastSync, Date().timeIntervalSince(last) > settings.interval {
            Task { await refresh() }
        }
        restartTimer()
    }

    func windowFocused() { refetchShown() }

    func setOnline(_ online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        guard cameBack else { return }
        refetchShown()
        Task {
            await refresh(force: true)
            restartTimer()
        }
    }

    private func refetchShown(force: Bool = false) {
        guard canFetch else { return }
        queries.refetchObserved(force: force, except: .queue)
    }

    func refresh(full: Bool = false, force: Bool = false) async {
        if full { await sync.requestFull() }
        guard canFetch else { return }
        if let seed = pendingSeed {
            pendingSeed = nil
            await sync.seed(seed, watching: watching)
        }
        bindQueue()
        guard (try? await queries.fetch(queueQuery, force: force)) != nil else { return }
        if await sync.fullPending { _ = try? await queries.fetch(queueQuery) }
    }

    func refreshVisible() async {
        refetchShown(force: true)
        await refresh()
    }

    private var queueQuery: CacheQuery<SyncOutcome> {
        let watching = watching
        return CacheQuery(
            key: .queue(watching: watching), tags: [.queue], staleAfter: .zero, forgetAfter: .seconds(3600),
            onSuccess: { [weak self] outcome in await self?.apply(outcome, watching: watching) },
            onError: { [weak self] error in self?.syncFailed(error) }
        ) { [sync] _ in try await sync.sync(watching: watching) }
    }

    private func bindQueue() {
        queueObserver = observing(queueObserver, queueQuery)
    }

    private func apply(_ outcome: SyncOutcome, watching synced: Set<String>) async {
        guard synced == watching else { return }
        let nova = outcome.queue
        let events = store.diff(nova, meuLogin: nova.viewer)
            .filter { e in
                let repo = e.key.split(separator: "#").first.map(String.init) ?? ""
                return !settings.mutedRepos.contains(repo)
            }
            .filter { e in
                guard e.kind == .reviewRequested,
                      let pr = nova.toReview.first(where: { $0.key == e.key }) else { return true }
                return !quiets(pr)
            }
        let candidates = settings.showsReviews
            ? Array(store.unrequested.filter { !reviewedAhead.contains($0.key) }.prefix(5)) : []
        if !candidates.isEmpty { onReviewsPending?(candidates.map(\.key), count) }
        queue = nova
        store.saveQueue(nova)
        reviewedAhead = reviewedAhead.filter { key in nova.toReview.contains { $0.key == key } }
        confirmReviews(candidates)
        if let s = selected {
            selected = nova.all.first { $0.key == s.key } ?? s
        }
        unread = store.state.unread
        lastSync = Date()
        if let stale = outcome.staleMessage {
            if let e = outcome.error { report(e, in: .refresh) }
            failures = 0
            partialFailures += 1
            errorMessage = stale
        } else {
            failures = 0
            partialFailures = 0
            errorMessage = nil
        }
        syncScreens()
        await notificador.post(events)
        onCountChange?()
        recordActiveDay()
        schedulePrefetch()
        schedulePreload()
        if !focus.isOn, let first = events.first(where: { $0.kind.interrupts }) {
            onEvent?(first)
        }
    }

    private func syncFailed(_ error: Error) {
        guard let m = report(error, in: .refresh) else { return }
        failures += 1
        errorMessage = m
    }

    var org: String {
        let donos = queue.all.compactMap { $0.repo.split(separator: "/").first.map(String.init) }
        let count = Dictionary(grouping: donos, by: { $0 }).mapValues(\.count)
        return count.max { $0.value < $1.value }?.key ?? ""
    }

    func toggleFollow(_ login: String) {
        store.toggleFollow(login)
        following = store.state.following
        syncScreens()
        if canFetch, settings.rankingMode == .team, let rankingQuery { queries.prefetch(rankingQuery) }
    }

    var notchTabs: [NotchTab] {
        NotchTab.allCases.filter { $0 != .ranking || settings.rankingMode != .off }
    }

    private func rankingModeChanged() {
        if settings.rankingMode == .off, notchTab == .ranking { notchTab = .queue }
        syncScreens()
    }

    func loadTab(_ tab: NotchTab) {
        shownTab = tab == .queue ? nil : tab
        syncScreens()
        refetchShown()
    }

    private var teamQuery: CacheQuery<[Person]>? {
        org.isEmpty ? nil : reporting(Queries.team(org: org), in: .loadTab)
    }

    private var rankingQuery: CacheQuery<[RankRow]>? { rankingQuery(for: team) }

    private func rankingQuery(for team: [Person]) -> CacheQuery<[RankRow]>? {
        guard !org.isEmpty, !team.isEmpty else { return nil }
        let logins = rankingScope(team).map(\.login)
        return reporting(Queries.ranking(org: org, period: rankPeriod, logins: logins), in: .loadTab)
    }

    private var activityQuery: CacheQuery<ActivityLog>? {
        guard !org.isEmpty, !queue.viewer.isEmpty else { return nil }
        return reporting(Queries.activity(org: org, login: queue.viewer), in: .loadTab)
    }

    private func reporting<T>(_ q: CacheQuery<T>, in operation: ErrorReport.Operation) -> CacheQuery<T> {
        var q = q
        q.retryDelays = Queries.networkRetries
        return q.onError { [weak self] error in
            guard let self, let m = self.report(error, in: operation) else { return }
            self.errorMessage = m
        }
    }

    private func syncScreens() {
        guard !syncingScreens else { return }
        syncingScreens = true
        defer { syncingScreens = false }
        let tab = shownTab
        let board = tab == .ranking && settings.rankingMode == .team
        let pace = tab == .ranking && settings.rankingMode == .pace
        teamObserver = observing(teamObserver, tab == .team || board ? teamQuery : nil)
        rankingObserver = observing(rankingObserver, board ? rankingQuery : nil, keepingPrevious: true)
        activityObserver = observing(activityObserver, tab == .activity || pace ? activityQuery : nil)
        reposObserver = observing(reposObserver, reposShown > 0 ? reposQuery : nil)
        repoObserver = observing(repoObserver, selectedRepo.map(repoQuery))
    }

    private func observing<T: Sendable>(
        _ current: QueryObserver<T>?, _ q: CacheQuery<T>?, keepingPrevious: Bool = false
    ) -> QueryObserver<T>? {
        guard let q else { return nil }
        if let current, current.key == q.key { return current }
        objectWillChange.send()
        return queries.observe(q, placeholder: keepingPrevious ? current?.data : nil)
    }

    var myRank: RankRow? { ranking.first { $0.person.login == queue.viewer } }

    var teammates: [Person] { Self.others(team, viewer: queue.viewer) }

    var pickedTeammates: Int { teammates.filter { following.contains($0.login) }.count }

    nonisolated static func others(_ people: [Person], viewer: String) -> [Person] {
        guard !viewer.isEmpty else { return people }
        return people.filter { $0.login.caseInsensitiveCompare(viewer) != .orderedSame }
    }

    private func rankingScope(_ all: [Person]) -> [Person] {
        let picked = all.filter { following.contains($0.login) || $0.login == queue.viewer }
        return picked.count >= 2 ? picked : Array(all.prefix(20))
    }

    func runAIReview(_ pr: PR) async {
        guard pr.isMine, !isReviewing(pr.key) else { return }
        let reviewStarted = Date()
        let deep = DeepReview.available
        runs[pr.key] = ReviewRun(step: .preparing("starting"), startedAt: reviewStarted)
        note(pr.key, "finding the repository")
        telemetry.capture(.aiReviewStarted(deep: deep))
        var outcome = TelemetryEvent.Outcome.failed
        var findings = 0
        var judged = 0
        defer {
            telemetry.capture(.aiReviewFinished(
                outcome: outcome, findings: findings, threadsJudged: judged, deep: deep,
                duration: .init(seconds: Date().timeIntervalSince(reviewStarted))
            ))
        }

        guard let origin = Worktree.localPath(pr.repo, configured: settings.repoPaths) else {
            runs[pr.key]?.step = .failed("could not find \(pr.repo) on this machine. Point at the folder in Settings.")
            note(pr.key, "repository not found", fechando: true)
            return
        }

        var target: URL?
        do {
            note(pr.key, "reading the PR, its threads and comments from GitHub")
            let context = try await reviewContext(for: pr)

            note(pr.key, "preparing the worktree")
            let w = try await Worktree.prepare(
                origin: origin, repo: pr.repo, pr: pr.number, base: context.base, head: context.head
            )
            target = w

            note(pr.key, DeepReview.available
                 ? "deep review: two axes, the value pass, then \(context.openThreads) open thread\(context.openThreads == 1 ? "" : "s")"
                 : "Claude is reading the code")
            let voice = Voice(
                samples: Voice.yours(in: queue),
                houseRules: Voice.houseRules(in: w)
            )
            for await step in Reviewer().review(
                pr: pr, context: context, viewer: queue.viewer,
                in: w, model: settings.aiModel, language: settings.reviewLanguage,
                voice: voice
            ) {
                runs[pr.key]?.step = step
                switch step {
                case .preparing(let t), .tool(let t): note(pr.key, t)
                case .thinking: note(pr.key, "thinking")
                case .done(let r):
                    queries.put(
                        reviewKey(pr), AIReview(result: r, context: context),
                        tags: [.pr(pr.key)], forgetAfter: Self.aiResultsForgetAfter
                    )
                    outcome = .done
                    findings = r.novel.count
                    judged = r.threads.count
                    let judged = r.threads.isEmpty ? "" : " · \(r.threads.count) thread\(r.threads.count == 1 ? "" : "s") judged"
                    note(pr.key, "\(r.novel.count) finding\(r.novel.count == 1 ? "" : "s")\(judged)", fechando: true)
                case .failed(let m): note(pr.key, m, fechando: true)
                }
            }
        } catch {
            report(error, in: .aiReview)
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

    static let aiResultsForgetAfter: Duration = .seconds(24 * 3600)

    private func putMap(_ map: PRMap, for stack: [PR]) {
        queries.put(mapKey(stack), map, tags: stack.map { .pr($0.key) }, forgetAfter: Self.aiResultsForgetAfter)
    }

    func stackOf(_ pr: PR) -> [PR] {
        queue.all.groupedIntoStacks().first { s in s.prs.contains { $0.key == pr.key } }?.prs ?? [pr]
    }

    func buildMap(_ pr: PR) async {
        let prs = stackOf(pr)
        let keys = Set(prs.map(\.key))
        guard !keys.contains(where: isMapping) else { return }
        let started = Date()
        func setRun(_ run: MapRun) {
            var all = mapRuns
            for k in keys { all[k] = run }
            mapRuns = all
        }
        func updateRun(_ change: (inout MapRun) -> Void) {
            var all = mapRuns
            for k in keys { if all[k] != nil { change(&all[k]!) } }
            mapRuns = all
        }
        func notice(_ text: String?) {
            var all = mapNotices
            for k in keys { all[k] = text }
            mapNotices = all
        }
        notice(nil)
        setRun(MapRun(
            phase: "reading the diff",
            startedAt: started,
            estimate: MapTiming.estimate(size: MapSize(), worktreeReady: true),
            expectedTools: 6
        ))
        var mapOutcome = TelemetryEvent.Outcome.failed
        defer {
            var all = mapRuns
            for k in keys { all[k] = nil }
            mapRuns = all
            telemetry.capture(.mapBuilt(
                outcome: mapOutcome, prsInStack: prs.count,
                duration: .init(seconds: Date().timeIntervalSince(started))
            ))
        }

        var map: PRMap
        var changedPaths = Set<String>()
        do {
            let scans = try await withThrowingTaskGroup(of: PRFiles.self) { group in
                for p in prs {
                    group.addTask { [queries] in try await queries.fetch(Queries.changedFiles(p)) }
                }
                var all: [PRFiles] = []
                for try await s in group { all.append(s) }
                let order = prs.map(\.number)
                return all.sorted { (order.firstIndex(of: $0.number) ?? 0) < (order.firstIndex(of: $1.number) ?? 0) }
            }
            map = MapScan.build(repo: pr.repo, prs: scans)
            changedPaths = Set(scans.flatMap { $0.files.map(\.path) })
        } catch {
            report(error, in: .mapDiff)
            notice("could not read the diff: \(error.localizedDescription)")
            return
        }
        putMap(map, for: prs)

        guard let origin = Worktree.localPath(pr.repo, configured: settings.repoPaths) else {
            notice("only the diff layer: \(pr.repo) is not on this machine. Point at the folder in Settings.")
            return
        }
        mapRoots[map.layoutKey] = [origin]

        let top = prs.last ?? pr
        let estimate = MapTiming.estimate(
            size: map.size,
            worktreeReady: Worktree.existing(repo: pr.repo, pr: top.number) != nil
        )
        setRun(MapRun(
            phase: "preparing the worktree",
            startedAt: started,
            estimate: estimate,
            expectedTools: MapTiming.expectedTools(map.size)
        ))

        do {
            let w = try await Worktree.prepare(origin: origin, repo: pr.repo, pr: top.number, base: map.base)
            mapRoots[map.layoutKey] = [w, origin]

            let titles = Dictionary(prs.map { ($0.number, $0.title) }, uniquingKeysWith: { f, _ in f })
            updateRun { $0.phase = "finding who depends on the change" }
            let candidates = await Dependents.find(
                changed: changedPaths,
                modules: Set(map.nodes(.changed).map(\.id)),
                in: w
            )
            updateRun { $0.phase = "Claude is reading the code" }
            var answered = false
            for await step in MapBuilder().enrich(
                map: map, titles: titles, candidates: candidates,
                in: w, model: settings.mapAIModel, language: settings.reviewLanguage
            ) {
                switch step {
                case .session(let s):
                    updateRun { $0.phase = s }
                case .tool(let t):
                    updateRun {
                        $0.toolCalls += 1
                        $0.lastTool = t
                        $0.phase = "Claude is reading the code"
                    }
                case .thinking:
                    break
                case .done(let answer):
                    if let a = answer {
                        answered = true
                        let fm = FileManager.default
                        map = map.merged(a) { fm.fileExists(atPath: w.appendingPathComponent($0).path) }
                        putMap(map, for: prs)
                    } else {
                        notice("only the diff layer: the session did not answer in the map's JSON")
                    }
                case .failed(let m):
                    notice("only the diff layer: \(m)")
                }
            }
            if answered {
                mapOutcome = .done
                MapTiming.record(raw: estimate.raw, actual: Date().timeIntervalSince(started), size: map.size)
            }
        } catch {
            report(error, in: .mapEnrich)
            notice("only the diff layer: \(error.localizedDescription)")
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
            var all = mapNotices
            for n in map.stack { all["\(map.repo)#\(n)"] = message }
            mapNotices = all
        }
    }

    func sendTestEvent(_ kind: EventKind) async {
        let pr = queue.all.first
        let event = Event(
            id: "teste/\(kind.rawValue)/\(Date().timeIntervalSince1970)",
            kind: kind,
            key: pr?.key ?? "example#1",
            url: pr?.url ?? URL(string: "https://github.com")!,
            title: testText(kind).0,
            body: pr.map { "\($0.key) · \($0.title)" } ?? testText(kind).1,
            isTest: true
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
        case .checkFailed:     ("A check failed on your PR", "checks / test · 1 of 5 failing")
        case .approved:       ("Your PR was approved", "ready to merge")
        case .newPullRequest: ("Lu opened a pull request", "console #4781 · in a repository you watch")
        }
    }

    func discardFinding(_ pr: PR, _ a: Finding) {
        queries.setData(reviewKey(pr)) { (review: inout AIReview) in
            review.result.findings.removeAll { $0.id == a.id }
        }
    }

    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    func open(_ pr: PR, from source: TelemetryEvent.Source = .window) {
        openURL(pr.url)
        telemetry.capture(.prOpened(source: source))
        store.markRead(pr.key)
        unread = store.state.unread
        watchForReview(pr)
    }

    func clearAll() {
        store.markAllRead()
        unread = store.state.unread
    }

    func flushState() { store.flushNow() }

    func settleState() async { await store.settle() }

    enum NeedsReason: Sendable, Equatable {
        case reviewRequested
        case replied
        case commented
        case checkFailed
        case approved
        case opened

        init(_ kind: EventKind) {
            switch kind {
            case .repliedToYou:    self = .replied
            case .commented:       self = .commented
            case .reviewRequested: self = .reviewRequested
            case .checkFailed:     self = .checkFailed
            case .approved:        self = .approved
            case .newPullRequest:  self = .opened
            }
        }

        var kind: EventKind {
            switch self {
            case .replied:         .repliedToYou
            case .commented:       .commented
            case .reviewRequested: .reviewRequested
            case .checkFailed:     .checkFailed
            case .approved:        .approved
            case .opened:          .newPullRequest
            }
        }

        static func of(
            _ key: String, unread: Set<String>, reasons: [String: EventKind], reviewRequested: Bool
        ) -> NeedsReason? {
            if unread.contains(key) { return reasons[key].map(NeedsReason.init) ?? .replied }
            return reviewRequested ? .reviewRequested : nil
        }

        var label: String {
            switch self {
            case .reviewRequested: "review requested"
            case .replied:         "replied to you"
            case .commented:       "new comment"
            case .checkFailed:     "check failing"
            case .approved:        "approved"
            case .opened:          "opened"
            }
        }
    }

    func needsReason(_ pr: PR) -> NeedsReason? {
        NeedsReason.of(
            pr.key,
            unread: unread,
            reasons: store.state.unreadReasons,
            reviewRequested: queue.toReview.contains { $0.key == pr.key }
        )
    }

    var needsYou: [PR] {
        var seen = Set<String>()
        var out: [PR] = []
        for pr in reviewing + queue.all.filter({ unread.contains($0.key) }) {
            guard pr.author != queue.viewer || unread.contains(pr.key) else { continue }
            guard !isQuiet(pr) else { continue }
            if seen.insert(pr.key).inserted { out.append(pr) }
        }
        return out
    }

    var reviewing: [PR] {
        settings.reviewFilter.order(queue.toReview.filter { !reviewedAhead.contains($0.key) }, picked: following)
    }

    func quiets(_ pr: PR) -> Bool { settings.reviewFilter.quiets(pr, picked: following) }

    func dims(_ pr: PR) -> Bool {
        quiets(pr) && queue.toReview.contains { $0.key == pr.key }
    }

    func isQuiet(_ pr: PR) -> Bool {
        guard dims(pr) else { return false }
        return ReviewFilter.staysQuiet(unread: unread.contains(pr.key), reason: store.state.unreadReasons[pr.key])
    }

    var yoursBroken: [PR] { queue.mine.filter { $0.checks == .failing } }

    var onReviewsPending: (([String], Int) -> Void)?
    var onNoReview: ((String) -> Void)?
    var onTick: ((ReviewTick) -> Void)?

    private func confirmReviews(_ candidates: [Store.Unrequested]) {
        guard !candidates.isEmpty else { return }
        Task { [weak self] in
            for c in candidates {
                guard let self else { return }
                if let review = try? await self.client.myReview(onPullRequest: c.key, since: c.since) {
                    self.counted(pr: c.key, at: review.at, verdict: ReviewVerdict(github: review.state))
                } else {
                    self.onNoReview?(c.key)
                }
            }
        }
    }

    private var watches: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    private var watchOrder: [String] = []
    var watchEvery: Duration = .seconds(10)
    var watchFor: TimeInterval = 30 * 60
    static let mostWatched = 3

    func watchForReview(_ pr: PR) {
        guard settings.showsReviews, !queries.answersLocally, pr.author != queue.viewer else { return }
        let key = pr.key
        watches[key]?.task.cancel()
        watchOrder.removeAll { $0 == key }
        watchOrder.append(key)
        while watchOrder.count > Self.mostWatched {
            let oldest = watchOrder.removeFirst()
            watches[oldest]?.task.cancel()
            watches[oldest] = nil
        }
        let id = UUID()
        let since = Date()
        let task = Task { [weak self] in
            while let self, !Task.isCancelled, Date().timeIntervalSince(since) < self.watchFor {
                try? await Task.sleep(for: self.watchEvery)
                guard !Task.isCancelled, self.queue.all.contains(where: { $0.key == key }) else { break }
                if let review = try? await self.client.myReview(onPullRequest: key, since: since) {
                    self.reviewedFromDiple(key, at: review.at, verdict: ReviewVerdict(github: review.state))
                    break
                }
            }
            guard let self, self.watches[key]?.id == id else { return }
            self.watches[key] = nil
            self.watchOrder.removeAll { $0 == key }
        }
        watches[key] = (id, task)
    }

    var watchedForReview: [String] { watchOrder }

    func reviewedFromDiple(_ key: String, at: Date, verdict: ReviewVerdict) {
        if queue.toReview.contains(where: { $0.key == key }), !reviewedAhead.contains(key) {
            onReviewsPending?([key], count)
            reviewedAhead.insert(key)
            onCountChange?()
        }
        counted(pr: key, at: at, verdict: verdict)
    }

    func counted(pr: String, at: Date, verdict: ReviewVerdict) {
        guard let today = store.countReview(pr, at: at) else { return onNoReview?(pr) ?? () }
        onTick?(ReviewTick(id: "\(pr)/\(at.timeIntervalSince1970)", pr: pr, verdict: verdict, today: today))
    }

    func rehearseReviews() {
        let prs = Array(reviewing.prefix(3))
        guard !prs.isEmpty else { return }
        let verdicts: [ReviewVerdict] = [.commented, .changesRequested, .approved]
        onReviewsPending?(prs.map(\.key), count)
        for (i, pr) in prs.enumerated() {
            reviewedAhead.insert(pr.key)
            counted(pr: pr.key, at: Date().addingTimeInterval(Double(i)), verdict: verdicts[i % verdicts.count])
        }
        onCountChange?()
    }

    var count: Int { needsYou.count }

    func prs(_ tab: Tab) -> [PR] {
        switch tab {
        case .needsYou:  needsYou
        case .mine:       queue.mine
        case .reviewing:  reviewing
        case .following: queue.following
        }
    }

    func count(_ tab: Tab) -> Int { prs(tab).count }

    @Published private(set) var requirements: [String: Int] = [:]

    static func requirementKey(_ pr: PR) -> String { "\(pr.repo)@\(pr.baseRef)" }

    func requiredApprovals(for pr: PR) -> Int? { requirements[Self.requirementKey(pr)] }

    func loadRequirements(for prs: [PR]) {
        guard !Demo.isOn else {
            requirements = Dictionary(prs.map { (Self.requirementKey($0), Demo.required) }, uniquingKeysWith: { a, _ in a })
            return
        }
        let wanted = Dictionary(prs.filter { !$0.draft }.map { (Self.requirementKey($0), $0) }, uniquingKeysWith: { a, _ in a })
        for (key, pr) in wanted where requirements[key] == nil {
            let q = Queries.requiredApprovals(repo: pr.repo, branch: pr.baseRef)
            queries.prefetch(q)
            Task { [weak self] in
                guard let found = try? await self?.queries.fetch(q) else { return }
                if let n = found.count { self?.requirements[key] = n }
            }
        }
    }

    func reply(thread: String, text: String) async -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        sending = true
        defer { sending = false }
        do {
            try await client.reply(threadId: thread, body: t)
            telemetry.capture(.replySent(source: .window))
            if let pr = selected { await reread(pr) } else { await refresh() }
            return nil
        } catch {
            report(error, in: .reply)
            return error.localizedDescription
        }
    }

    func resolve(thread: String) async -> String? {
        sending = true
        defer { sending = false }
        do {
            try await client.resolve(threadId: thread)
            telemetry.capture(.threadResolved(source: .window))
            if let pr = selected { await reread(pr) } else { await refresh() }
            return nil
        } catch {
            report(error, in: .resolve)
            return error.localizedDescription
        }
    }

    var rest: [PR] {
        let urgentes = Set(needsYou.map(\.key))
        return queue.mine.filter { !urgentes.contains($0.key) }
    }
}
