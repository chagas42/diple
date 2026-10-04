import Foundation

struct Snapshot: Codable, Sendable, Equatable {
    var updatedAt: Date
    var checks: String
    var approved: Bool
    var lastCommentAt: Date?
    var reviewRequested: Bool
}

struct StoredState: Codable, Sendable, Equatable {
    var version = 1
    var prs: [String: Snapshot] = [:]
    var unread: Set<String> = []
    var unreadReasons: [String: EventKind] = [:]

    var hasRunBefore: Bool = false
    var watchedSince: [String: Date]? = nil

    var following: Set<String> = []
    var watching: Set<String>? = nil
    var settings = Settings()
    var cache = Cache()
    var installId: String? = nil
    var usageNoticeSeen = false
    var lastActiveDay: String? = nil
    var requestSeenAt: [String: Date] = [:]
    var countedReviews: [String: Date] = [:]
    var reviewDay: String? = nil
    var reviewsThatDay = 0
    var dismissed: [String: Date]? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = StoredState()
        d.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        d.prs = try c.decodeIfPresent([String: Snapshot].self, forKey: .prs) ?? d.prs
        d.unread = try c.decodeIfPresent(Set<String>.self, forKey: .unread) ?? d.unread
        d.unreadReasons = (try? c.decodeIfPresent([String: EventKind].self, forKey: .unreadReasons)) ?? d.unreadReasons
        d.hasRunBefore = try c.decodeIfPresent(Bool.self, forKey: .hasRunBefore) ?? d.hasRunBefore
        d.watchedSince = try c.decodeIfPresent([String: Date].self, forKey: .watchedSince)
        d.following = try c.decodeIfPresent(Set<String>.self, forKey: .following) ?? d.following
        d.watching = try c.decodeIfPresent(Set<String>.self, forKey: .watching) ?? d.watching
        d.settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? d.settings
        d.cache = try c.decodeIfPresent(Cache.self, forKey: .cache) ?? d.cache
        d.installId = try c.decodeIfPresent(String.self, forKey: .installId)
        d.usageNoticeSeen = try c.decodeIfPresent(Bool.self, forKey: .usageNoticeSeen) ?? d.usageNoticeSeen
        d.lastActiveDay = try c.decodeIfPresent(String.self, forKey: .lastActiveDay)
        d.requestSeenAt = (try? c.decodeIfPresent([String: Date].self, forKey: .requestSeenAt)) ?? d.requestSeenAt
        d.countedReviews = (try? c.decodeIfPresent([String: Date].self, forKey: .countedReviews)) ?? d.countedReviews
        d.reviewDay = try c.decodeIfPresent(String.self, forKey: .reviewDay)
        d.reviewsThatDay = try c.decodeIfPresent(Int.self, forKey: .reviewsThatDay) ?? d.reviewsThatDay
        d.dismissed = try? c.decodeIfPresent([String: Date].self, forKey: .dismissed)
        self = d
    }

}

enum RankPeriod: String, CaseIterable, Codable, Sendable, Identifiable {
    case week, month, quarter
    var id: String { rawValue }

    var label: String {
        switch self {
        case .week:    "Week"
        case .month:   "Month"
        case .quarter: "Quarter"
        }
    }

    var caption: String {
        switch self {
        case .week:    "this week"
        case .month:   "this month"
        case .quarter: "this quarter"
        }
    }

    var since: Date { since(now: Date()) }

    func since(now: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        switch self {
        case .week:
            return cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        case .month:
            return cal.dateInterval(of: .month, for: now)?.start ?? cal.startOfDay(for: now)
        case .quarter:
            let month = cal.component(.month, from: now)
            var start = cal.dateComponents([.year], from: now)
            start.month = (month - 1) / 3 * 3 + 1
            start.day = 1
            return cal.date(from: start) ?? cal.startOfDay(for: now)
        }
    }

    func startDay(now: Date = Date(), calendar: Calendar = .current) -> String {
        Self.day(since(now: now, calendar: calendar), calendar: calendar)
    }

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        fmt.timeZone = calendar.timeZone
        return fmt.string(from: date)
    }

    var freshFor: TimeInterval {
        switch self {
        case .week:    600
        case .month:   1800
        case .quarter: 3600
        }
    }
}

struct Cache: Codable, Sendable, Equatable {
    var scoreShownOn: Date?
    var lastQueue: Lenient<Queue>? = nil
    var queries: [String: StoredQuery]? = nil

    var queue: Queue? {
        get { lastQueue?.value }
        set { lastQueue = newValue.map(Lenient.init) }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = Cache()
        d.scoreShownOn = try c.decodeIfPresent(Date.self, forKey: .scoreShownOn)
        d.lastQueue = try? c.decodeIfPresent(Lenient<Queue>.self, forKey: .lastQueue)
        d.queries = try? c.decodeIfPresent([String: StoredQuery].self, forKey: .queries)
        self = d
    }

}

struct Lenient<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    var value: Value?

    init(_ value: Value?) { self.value = value }

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

@MainActor
final class Store {
    private(set) var state = StoredState()

    static var defaultDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["DIPLE_STATE_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diple", isDirectory: true)
    }

    private let path: URL
    private let writer: StoreWriter
    private var generation = 0

    init(
        directory: URL = Store.defaultDirectory,
        metrics: Metrics = .shared,
        debounce: Duration = .milliseconds(500)
    ) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("state.json")
        writer = StoreWriter(path: path, metrics: metrics, debounce: debounce)
        load()
        writer.assumeOnDisk(state)
    }

    private func load() {
        guard let bytes = try? Data(contentsOf: path) else { return }
        if let decoded = try? JSONDecoder().decode(StoredState.self, from: bytes) {
            state = decoded
            return
        }
        let backup = path.deletingLastPathComponent()
            .appendingPathComponent("state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: path, to: backup)
        FileHandle.standardError.write(Data(
            "diple: could not read \(path.lastPathComponent), kept a copy at \(backup.lastPathComponent)\n".utf8
        ))
    }

    private func save() {
        generation += 1
        let snapshot = state
        let g = generation
        Task { [writer] in await writer.schedule(snapshot, generation: g) }
    }

    func settle() async {
        await writer.schedule(state, generation: generation)
        await writer.flush()
    }

    func flushNow() {
        generation += 1
        writer.writeNow(state, generation: generation)
    }

    func ensureInstallId() -> String {
        if let id = state.installId, !id.isEmpty { return id }
        let id = UUID().uuidString.lowercased()
        state.installId = id
        save()
        return id
    }

    func resetInstallId() -> String {
        let id = UUID().uuidString.lowercased()
        state.installId = id
        save()
        return id
    }

    func markUsageNoticeSeen() {
        state.usageNoticeSeen = true
        save()
    }

    func markActive(on day: String) -> Bool {
        guard state.lastActiveDay != day else { return false }
        state.lastActiveDay = day
        save()
        return true
    }

    func markRead(_ key: String) {
        state.unread.remove(key)
        state.unreadReasons[key] = nil
        save()
    }

    func dismiss(_ pr: PR) {
        state.dismissed = (state.dismissed ?? [:]).merging([pr.key: pr.updatedAt]) { _, new in new }
        state.unread.remove(pr.key)
        state.unreadReasons[pr.key] = nil
        save()
    }

    func forgetDismissals(_ queue: Queue, now: Date = Date()) {
        guard let dismissed = state.dismissed else { return }
        let kept = Dismissals.kept(dismissed, queue: queue, now: now)
        guard kept != dismissed else { return }
        state.dismissed = kept
        save()
    }

    func updateCache(_ change: (inout Cache) -> Void) {
        change(&state.cache)
        save()
    }

    func saveQueue(_ q: Queue) {
        var q = q
        q.rateLimitLeft = 0
        q.rateLimitResetAt = nil
        state.cache.queue = q
        save()
    }

    func saveSettings(_ c: Settings) {
        state.settings = c
        save()
    }

    func toggleWatch(_ repo: String) {
        var w = state.watching ?? []
        var since = state.watchedSince ?? [:]
        if w.contains(repo) {
            w.remove(repo)
            since[repo] = nil
        } else {
            w.insert(repo)
            since[repo] = Date()
        }
        state.watching = w
        state.watchedSince = since
        save()
    }

    func toggleFollow(_ login: String) {
        if state.following.contains(login) { state.following.remove(login) }
        else { state.following.insert(login) }
        save()
    }

    func markAllRead() {
        state.unread.removeAll()
        state.unreadReasons.removeAll()
        save()
    }

    struct Unrequested: Equatable, Sendable {
        let key: String
        let since: Date
    }

    private(set) var unrequested: [Unrequested] = []

    static func day(of date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func reviewsToday(now: Date = Date()) -> Int {
        state.reviewDay == Self.day(of: now) ? state.reviewsThatDay : 0
    }

    func countReview(_ key: String, at: Date, now: Date = Date()) -> Int? {
        if let last = state.countedReviews[key], abs(last.timeIntervalSince(at)) < 1 { return nil }
        state.countedReviews = state.countedReviews.filter { now.timeIntervalSince($0.value) < 2 * 86_400 }
        state.countedReviews[key] = at
        let today = Self.day(of: now)
        if state.reviewDay != today {
            state.reviewDay = today
            state.reviewsThatDay = 0
        }
        state.reviewsThatDay += 1
        save()
        return state.reviewsThatDay
    }

    func diff(_ queue: Queue, meuLogin: String) -> [Event] {
        var events: [Event] = []
        var next: [String: Snapshot] = [:]
        let estreia = !state.hasRunBefore

        let reviewRequested = Set(queue.toReview.map(\.key))

        for pr in queue.all {
            let now = Snapshot(
                updatedAt: pr.updatedAt,
                checks: pr.checks.rawValue,
                approved: pr.approved,
                lastCommentAt: pr.lastComment?.at,
                reviewRequested: reviewRequested.contains(pr.key)
            )
            next[pr.key] = now

            guard !estreia else { continue }
            let before = state.prs[pr.key]

            if now.reviewRequested, before?.reviewRequested != true {
                state.requestSeenAt[pr.key] = Date()
                events.append(Event(
                    id: "\(pr.key)/review/\(pr.updatedAt.timeIntervalSince1970)",
                    kind: .reviewRequested, key: pr.key, url: pr.url,
                    title: "\(pr.author) requested your review",
                    body: "\(pr.key) · \(pr.title)"
                ))
            }

            if pr.isMine, now.checks == CheckState.failing.rawValue,
               let a = before, a.checks != CheckState.failing.rawValue {
                events.append(Event(
                    id: "\(pr.key)/checks/\(pr.updatedAt.timeIntervalSince1970)",
                    kind: .checkFailed, key: pr.key, url: pr.url,
                    title: "A check failed on your PR",
                    body: "\(pr.key) · \(pr.title)"
                ))
            }

            if let c = pr.lastComment,
               before?.lastCommentAt != c.at,
               before != nil {
                let mentionsYou = c.excerpt.localizedCaseInsensitiveContains("@\(meuLogin)")
                events.append(Event(
                    id: "\(pr.key)/message/\(c.at.timeIntervalSince1970)",
                    kind: mentionsYou ? .repliedToYou : .commented,
                    key: pr.key, url: pr.url,
                    title: mentionsYou ? "\(c.author) replied to you" : "\(c.author) commented on your PR",
                    body: c.location.map { "\($0) — \(c.excerpt)" } ?? c.excerpt,
                    threadId: c.threadId
                ))
            }

            if pr.isMine, now.approved, before?.approved == false {
                events.append(Event(
                    id: "\(pr.key)/ok/\(pr.updatedAt.timeIntervalSince1970)",
                    kind: .approved, key: pr.key, url: pr.url,
                    title: "Your PR was approved",
                    body: "\(pr.key) · \(pr.title)"
                ))
            }
        }

        let since = state.watchedSince ?? [:]
        for pr in queue.watched where !estreia && !pr.draft {
            guard state.prs[pr.key] == nil else { continue }
            guard let from = since[pr.repo], pr.createdAt > from else { continue }
            next[pr.key] = Snapshot(
                updatedAt: pr.updatedAt, checks: pr.checks.rawValue, approved: pr.approved,
                lastCommentAt: pr.lastComment?.at, reviewRequested: false
            )
            events.append(Event(
                id: "\(pr.key)/new/\(pr.createdAt.timeIntervalSince1970)",
                kind: .newPullRequest, key: pr.key, url: pr.url,
                title: "\(pr.author) opened a pull request",
                body: "\(pr.key) · \(pr.title)"
            ))
        }

        unrequested = state.hasRunBefore ? state.prs.compactMap { key, before in
            guard before.reviewRequested, next[key]?.reviewRequested != true else { return nil }
            return Unrequested(key: key, since: state.requestSeenAt[key] ?? before.updatedAt)
        } : []
        for key in state.requestSeenAt.keys where next[key]?.reviewRequested != true {
            state.requestSeenAt[key] = nil
        }

        state.prs = next
        state.hasRunBefore = true
        for e in events {
            state.unread.insert(e.key)
            state.unreadReasons[e.key] = EventKind.moreUrgent(state.unreadReasons[e.key], e.kind)
        }
        for pr in queue.all where state.unreadReasons[pr.key] == .checkFailed && pr.checks != .failing {
            state.unread.remove(pr.key)
            state.unreadReasons[pr.key] = nil
        }
        save()
        return events
    }
}
