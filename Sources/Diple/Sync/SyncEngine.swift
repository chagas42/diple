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
        lastFull = now()
    }

    private var watching: Set<String> = []

    func setWatching(_ w: Set<String>) { watching = w }

    func sync(full: Bool = false) async throws -> Queue {
        if full || needsReconcile {
            return try await fullSync()
        }
        let beat = try await client.fetchHeartbeat()
        let changed = beat.changed(since: known)
        var merged = known
        if !changed.isEmpty {
            let fetched = try await client.fetchPRs(ids: changed)
            guard Set(fetched.map(\.id)).isSuperset(of: changed) else { return try await fullSync() }
            for pr in fetched { merged[pr.id] = pr }
        }
        guard let queue = beat.queue(known: merged) else {
            return try await fullSync()
        }
        remember(queue)
        lastKind = changed.isEmpty ? .heartbeat : .heartbeatWithDetails
        return queue
    }

    private var needsReconcile: Bool {
        guard !known.isEmpty, let lastFull else { return true }
        return now().timeIntervalSince(lastFull) >= reconcileEvery
    }

    private func fullSync() async throws -> Queue {
        let queue = try await client.fetchQueue(watching: watching)
        known = [:]
        remember(queue)
        lastFull = now()
        lastKind = .full
        return queue
    }

    private func remember(_ queue: Queue) {
        known = Dictionary(queue.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
