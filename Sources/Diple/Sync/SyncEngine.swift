import Foundation

actor SyncEngine {
    enum Kind: String, Sendable {
        case full, heartbeat, heartbeatWithDetails
    }

    private let client: GitHubClient
    private let reconcileEvery: TimeInterval
    private let now: @Sendable () -> Date

    private var known: [String: PR] = [:]
    private var lastFull: Date?
    private var lastQueue: Queue?
    private var retryFull = false
    private(set) var lastKind: Kind?

    init(
        client: GitHubClient,
        reconcileEvery: TimeInterval = 1800,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.reconcileEvery = reconcileEvery
        self.now = now
    }

    func seed(_ queue: Queue) {
        guard known.isEmpty, !queue.all.isEmpty else { return }
        remember(queue)
        lastQueue = queue
        lastFull = now()
    }

    private var watching: Set<String> = []

    func setWatching(_ w: Set<String>) { watching = w }

    func sync(full: Bool = false) async throws -> SyncOutcome {
        if full || needsReconcile {
            return try await fullSync()
        }
        let beat = try await client.fetchHeartbeat()
        let changed = beat.changed(since: known)
        var merged = known
        var detail = GitHubClient.DetailFetch()
        if !changed.isEmpty {
            detail = await client.fetchPRs(ids: changed)
            let answered = Set(changed).subtracting(detail.failed)
            guard Set(detail.prs.map(\.id)).isSuperset(of: answered) else { return try await fullSync() }
            for pr in detail.prs { merged[pr.id] = pr }
        }
        let unseen = detail.failed.filter { merged[$0] == nil }
        guard let queue = beat.queue(known: merged, skipping: unseen) else {
            return try await fullSync()
        }
        remember(queue)
        lastQueue = queue
        lastKind = changed.isEmpty ? .heartbeat : .heartbeatWithDetails
        return SyncOutcome(queue: queue, stalePRs: detail.failed.count, error: detail.error)
    }

    private var needsReconcile: Bool {
        guard !known.isEmpty, let lastFull, !retryFull else { return true }
        return now().timeIntervalSince(lastFull) >= reconcileEvery
    }

    private func fullSync() async throws -> SyncOutcome {
        let fetch = await client.fetchSections(watching: watching)
        let failed = Queue.Section.allCases.filter { fetch.failures[$0] != nil }
        if fetch.sections.isEmpty, let first = failed.first, let error = fetch.failures[first] {
            throw error
        }
        var queue = Queue(
            viewer: fetch.viewer ?? lastQueue?.viewer ?? "",
            rateLimitLeft: fetch.rateLimitLeft ?? 0,
            rateLimitResetAt: fetch.rateLimitResetAt
        )
        for (section, prs) in fetch.sections { queue[section] = prs }
        for section in failed { queue[section] = lastQueue?[section] ?? [] }
        known = [:]
        remember(queue)
        lastQueue = queue
        retryFull = !failed.isEmpty
        if failed.isEmpty { lastFull = now() }
        lastKind = .full
        return SyncOutcome(queue: queue, staleSections: failed, error: failed.first.flatMap { fetch.failures[$0] })
    }

    private func remember(_ queue: Queue) {
        known = Dictionary(queue.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

struct SyncOutcome: Sendable {
    var queue: Queue
    var staleSections: [Queue.Section] = []
    var stalePRs = 0
    var error: (any Error)?

    var staleMessage: String? {
        if !staleSections.isEmpty {
            let names = staleSections.map(\.title).joined(separator: ", ")
            return "\(names) could not sync — showing what it had"
        }
        if stalePRs > 0 {
            return "\(stalePRs) pull request\(stalePRs == 1 ? "" : "s") could not update — showing what \(stalePRs == 1 ? "it" : "they") had"
        }
        return nil
    }
}
