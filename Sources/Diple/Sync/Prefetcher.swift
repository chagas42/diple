import Foundation

actor Prefetcher {
    struct Target: Sendable {
        let pr: PR
        let origin: URL?
    }

    typealias FetchRefs = @Sendable (_ origin: URL, _ pr: Int, _ base: String) async throws -> Void

    static let depth = 5

    let queries: QueryClient
    private let concurrency: Int
    private let fetchRefs: FetchRefs

    private var refs: [String: Date] = [:]
    private var attempted: [String: Date] = [:]

    init(
        queries: QueryClient,
        concurrency: Int = 3,
        fetchRefs: @escaping FetchRefs = { try await Worktree.prefetchPR(origin: $0, pr: $1, base: $2) }
    ) {
        self.queries = queries
        self.concurrency = concurrency
        self.fetchRefs = fetchRefs
    }

    func context(for pr: PR) async -> ReviewContext? {
        await queries.cached(Queries.reviewContext(pr).key)
    }

    func changedFiles(for pr: PR) async -> PRFiles? {
        await queries.cached(Queries.changedFiles(pr).key)
    }

    func warm(_ targets: [Target]) async {
        var todo: [Target] = []
        for t in targets where await isStale(t) { todo.append(t) }
        await withTaskGroup(of: Void.self) { group in
            var pending = todo.makeIterator()
            for _ in 0..<concurrency {
                guard let t = pending.next() else { break }
                group.addTask { await self.warmOne(t) }
            }
            while await group.next() != nil {
                guard let t = pending.next() else { continue }
                group.addTask { await self.warmOne(t) }
            }
        }
    }

    private func isStale(_ t: Target) async -> Bool {
        let at = t.pr.updatedAt
        guard attempted[t.pr.key] != at else { return false }
        if t.origin != nil && refs[t.pr.key] != at { return true }
        if await changedFiles(for: t.pr) == nil { return true }
        return t.pr.isMine ? await context(for: t.pr) == nil : false
    }

    private func warmOne(_ t: Target) async {
        let pr = t.pr
        attempted[pr.key] = pr.updatedAt
        let queries = self.queries
        async let scan = try? queries.fetch(Queries.changedFiles(pr))
        var context: ReviewContext?
        if pr.isMine {
            context = try? await queries.fetch(Queries.reviewContext(pr))
        }
        let s = await scan
        if let origin = t.origin, refs[pr.key] != pr.updatedAt, let base = context?.base ?? s?.base {
            if (try? await fetchRefs(origin, pr.number, base)) != nil {
                refs[pr.key] = pr.updatedAt
            }
        }
    }
}
