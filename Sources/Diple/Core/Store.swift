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

    var hasRunBefore: Bool = false

    var following: Set<String> = []
    var watching: Set<String>? = nil
    var settings = Settings()
    var cache = Cache()
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
}

@MainActor
final class Store {
    private(set) var state = StoredState()

    private let path: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diple", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("state.json")
    }()

    init() { load() }

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
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(state).write(to: path, options: .atomic)
    }

    func markRead(_ key: String) {
        state.unread.remove(key)
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
        save()
    }

    func diff(_ queue: Queue, viewerLogin: String) -> [Event] {
        var events: [Event] = []
        var next: [String: Snapshot] = [:]
        let firstRun = !state.hasRunBefore

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

            guard !firstRun else { continue }
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
                let mentionsYou = c.excerpt.localizedCaseInsensitiveContains("@\(viewerLogin)")
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
        for e in events { state.unread.insert(e.key) }
        save()
        return events
    }
}
