import Foundation

actor Prefetcher {
    struct Target: Sendable {
        let pr: PR
        let origin: URL?
    }

    typealias FetchRefs = @Sendable (_ origin: URL, _ pr: Int, _ base: String) async throws -> Void

    static let depth = 5

    private let client: GitHubClient
    private let concurrency: Int
    private let fetchRefs: FetchRefs

    private var contexts: [String: (Date, ReviewContext)] = [:]
    private var files: [String: (Date, PRFiles)] = [:]
    private var refs: [String: Date] = [:]
    private var attempted: [String: Date] = [:]

    init(
        client: GitHubClient,
        concurrency: Int = 3,
        fetchRefs: @escaping FetchRefs = { try await Worktree.prefetchPR(origin: $0, pr: $1, base: $2) }
    ) {
        self.client = client
        self.concurrency = concurrency
        self.fetchRefs = fetchRefs
    }

    func context(for pr: PR) -> ReviewContext? {
        guard let (at, context) = contexts[pr.key], at == pr.updatedAt else { return nil }
        return context
    }

    func changedFiles(for pr: PR) -> PRFiles? {
        guard let (at, scan) = files[pr.key], at == pr.updatedAt else { return nil }
        return scan
    }

    func warm(_ targets: [Target]) async {
        let todo = targets.filter { isStale($0) }
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

    private func isStale(_ t: Target) -> Bool {
        let at = t.pr.updatedAt
        guard attempted[t.pr.key] != at else { return false }
        return (t.pr.isMine && contexts[t.pr.key]?.0 != at)
            || files[t.pr.key]?.0 != at
            || (t.origin != nil && refs[t.pr.key] != at)
    }

    private func warmOne(_ t: Target) async {
        let pr = t.pr
        attempted[pr.key] = pr.updatedAt
        let client = self.client
        async let scan = try? client.changedFiles(repo: pr.repo, pr: pr.number)
        var context: ReviewContext?
        if pr.isMine {
            context = try? await client.reviewContext(repo: pr.repo, pr: pr.number)
        }
        if let context {
            contexts[pr.key] = (pr.updatedAt, context)
        }
        let s = await scan
        if let s {
            files[pr.key] = (pr.updatedAt, s)
        }
        if let origin = t.origin, refs[pr.key] != pr.updatedAt, let base = context?.base ?? s?.base {
            if (try? await fetchRefs(origin, pr.number, base)) != nil {
                refs[pr.key] = pr.updatedAt
            }
        }
    }
}
