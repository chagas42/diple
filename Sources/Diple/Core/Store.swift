import Foundation

struct Snapshot: Codable, Sendable, Equatable {
    var updatedAt: Date
    var checks: String
    var approved: Bool
    var lastCommentAt: Date?
    var reviewRequested: Bool
}

struct StoredState: Codable, Sendable {
    var version = 1
    var prs: [String: Snapshot] = [:]
    var unread: Set<String> = []
    var unreadReasons: [String: EventKind] = [:]

    var hasRunBefore: Bool = false

    var following: Set<String> = []
    var watching: Set<String>? = nil
    var settings = Settings()
    var cache = Cache()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = StoredState()
        d.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        d.prs = try c.decodeIfPresent([String: Snapshot].self, forKey: .prs) ?? d.prs
        d.unread = try c.decodeIfPresent(Set<String>.self, forKey: .unread) ?? d.unread
        d.unreadReasons = (try? c.decodeIfPresent([String: EventKind].self, forKey: .unreadReasons)) ?? d.unreadReasons
        d.hasRunBefore = try c.decodeIfPresent(Bool.self, forKey: .hasRunBefore) ?? d.hasRunBefore
        d.following = try c.decodeIfPresent(Set<String>.self, forKey: .following) ?? d.following
        d.watching = try c.decodeIfPresent(Set<String>.self, forKey: .watching) ?? d.watching
        d.settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? d.settings
        d.cache = try c.decodeIfPresent(Cache.self, forKey: .cache) ?? d.cache
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
        case .week:    "last 7 days"
        case .month:   "last 30 days"
        case .quarter: "last 3 months"
        }
    }

    var since: Date {
        let cal = Calendar.current
        let now = Date()
        return switch self {
        case .week:    cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:   cal.date(byAdding: .day, value: -30, to: now) ?? now
        case .quarter: cal.date(byAdding: .month, value: -3, to: now) ?? now
        }
    }

    var freshFor: TimeInterval {
        switch self {
        case .week:    600
        case .month:   1800
        case .quarter: 3600
        }
    }
}

struct Cache: Codable, Sendable {
    var team: [Person] = []
    var ranking: [RankRow] = []
    var activity: [ActivityDay] = []
    var teamAt: Date?
    var rankingAt: Date?
    var activityAt: Date?
    var scoreShownOn: Date?
    var repos: [RepoRef]? = nil
    var reposAt: Date? = nil
    var rankByPeriod: [String: [RankRow]]? = nil
    var rankAtByPeriod: [String: Date]? = nil

    func rank(_ p: RankPeriod) -> [RankRow] { rankByPeriod?[p.rawValue] ?? [] }
    func rankAt(_ p: RankPeriod) -> Date? { rankAtByPeriod?[p.rawValue] }

    mutating func setRank(_ rows: [RankRow], for p: RankPeriod) {
        var byP = rankByPeriod ?? [:]
        byP[p.rawValue] = rows
        rankByPeriod = byP
        var atP = rankAtByPeriod ?? [:]
        atP[p.rawValue] = Date()
        rankAtByPeriod = atP
    }

    mutating func dropRanks() {
        rankByPeriod = nil
        rankAtByPeriod = nil
    }

    func isStale(_ at: Date?, after seconds: TimeInterval) -> Bool {
        guard let at else { return true }
        return Date().timeIntervalSince(at) > seconds
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = Cache()
        d.team = try c.decodeIfPresent([Person].self, forKey: .team) ?? d.team
        d.ranking = try c.decodeIfPresent([RankRow].self, forKey: .ranking) ?? d.ranking
        d.activity = try c.decodeIfPresent([ActivityDay].self, forKey: .activity) ?? d.activity
        d.teamAt = try c.decodeIfPresent(Date.self, forKey: .teamAt)
        d.rankingAt = try c.decodeIfPresent(Date.self, forKey: .rankingAt)
        d.activityAt = try c.decodeIfPresent(Date.self, forKey: .activityAt)
        d.scoreShownOn = try c.decodeIfPresent(Date.self, forKey: .scoreShownOn)
        d.repos = try c.decodeIfPresent([RepoRef].self, forKey: .repos)
        d.reposAt = try c.decodeIfPresent(Date.self, forKey: .reposAt)
        d.rankByPeriod = try c.decodeIfPresent([String: [RankRow]].self, forKey: .rankByPeriod)
        d.rankAtByPeriod = try c.decodeIfPresent([String: Date].self, forKey: .rankAtByPeriod)
        self = d
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
    private let metrics: Metrics

    init(directory: URL = Store.defaultDirectory, metrics: Metrics = .shared) {
        self.metrics = metrics
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("state.json")
        load()
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
        metrics.measure(.storeWrite) {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(state).write(to: path, options: .atomic)
        }
        metrics.count(.storeWrites)
        if Thread.isMainThread { metrics.count(.storeWritesOnMain) }
    }

    func markRead(_ key: String) {
        state.unread.remove(key)
        state.unreadReasons[key] = nil
        save()
    }

    func saveCache(_ c: Cache) {
        state.cache = c
        save()
    }

    func saveSettings(_ c: Settings) {
        state.settings = c
        save()
    }

    func toggleWatch(_ repo: String) {
        var w = state.watching ?? []
        if w.contains(repo) { w.remove(repo) } else { w.insert(repo) }
        state.watching = w
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
