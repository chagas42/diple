import Foundation

struct Beat: Sendable, Equatable {
    let updatedAt: Date
    let draft: Bool
    let checks: CheckState
    let approved: Bool
    var mergeable: Mergeable? = nil

    init(updatedAt: Date, draft: Bool, checks: CheckState, approved: Bool, mergeable: Mergeable? = nil) {
        self.updatedAt = updatedAt
        self.draft = draft
        self.checks = checks
        self.approved = approved
        self.mergeable = mergeable
    }

    init(_ pr: PR) {
        self.init(updatedAt: pr.updatedAt, draft: pr.draft, checks: pr.checks, approved: pr.approved,
                  mergeable: pr.mergeable)
    }

    func matches(_ fresh: Beat) -> Bool {
        guard updatedAt == fresh.updatedAt, draft == fresh.draft, checks == fresh.checks, approved == fresh.approved
        else { return false }
        guard let now = fresh.mergeable, now != .unknown else { return true }
        return now == mergeable
    }
}

struct Heartbeat: Sendable, Equatable {
    struct Row: Sendable, Equatable {
        let id: String
        let beat: Beat
    }

    var viewer: String
    var mine: [Row]
    var toReview: [Row]
    var following: [Row]
    var rateLimitLeft: Int
    var rateLimitResetAt: Date? = nil

    var all: [Row] { mine + toReview + following }

    func changed(since previous: [String: PR]) -> [String] {
        var seen = Set<String>()
        return all.compactMap { row in
            guard seen.insert(row.id).inserted else { return nil }
            guard let known = previous[row.id], Beat(known).matches(row.beat) else { return row.id }
            return nil
        }
    }

    func queue(known: [String: PR], skipping: Set<String> = []) -> Queue? {
        func section(_ rows: [Row]) -> [PR]? {
            var out: [PR] = []
            for row in rows where !skipping.contains(row.id) {
                guard let pr = known[row.id] else { return nil }
                out.append(pr)
            }
            return out
        }
        guard let m = section(mine), let r = section(toReview), let f = section(following) else { return nil }
        return Queue(
            viewer: viewer, mine: m, toReview: r, following: f,
            rateLimitLeft: rateLimitLeft, rateLimitResetAt: rateLimitResetAt
        )
    }
}

struct RawHeartbeat: Decodable, Sendable {
    let data: Payload?
    let errors: [GraphQLError]?

    struct Payload: Decodable, Sendable {
        let viewer: RawResponse.RawViewer
        let section: Search
        let rateLimit: RawResponse.RawRateLimit?
    }

    struct Search: Decodable, Sendable { let nodes: [Node?] }

    struct Node: Decodable, Sendable {
        let id: String
        let updatedAt: Date
        let isDraft: Bool
        let reviewDecision: String?
        var mergeable: String? = nil
        let commits: RawPR.RawCommits

        var row: Heartbeat.Row {
            Heartbeat.Row(id: id, beat: Beat(
                updatedAt: updatedAt,
                draft: isDraft,
                checks: CheckState(commits.nodes.compactMap { $0 }.first?.commit.statusCheckRollup?.state),
                approved: reviewDecision == "APPROVED",
                mergeable: mergeable.map(Mergeable.init(github:))
            ))
        }
    }
}

struct RawDetails: Decodable, Sendable {
    let data: Payload?
    let errors: [GraphQLError]?

    struct Payload: Decodable, Sendable {
        let viewer: RawResponse.RawViewer
        let nodes: [RawPR?]
    }
}

extension GitHubClient {
    func fetchHeartbeat() async throws -> Heartbeat {
        let searches = Query.heartbeatSearches
        async let mine = beat(searches[0])
        async let toReview = beat(searches[1])
        async let following = beat(searches[2])
        let sections = try await [mine, toReview, following]
        return Heartbeat(
            viewer: sections[0].viewer.login,
            mine: sections[0].section.nodes.compactMap { $0?.row },
            toReview: sections[1].section.nodes.compactMap { $0?.row },
            following: sections[2].section.nodes.compactMap { $0?.row },
            rateLimitLeft: sections.compactMap { $0.rateLimit?.remaining }.min() ?? 0,
            rateLimitResetAt: sections.compactMap { $0.rateLimit?.resetAt }.max()
        )
    }

    private func beat(_ search: String) async throws -> RawHeartbeat.Payload {
        let body: RawHeartbeat = try await send(Query.heartbeat(search))
        if let errors = body.errors, !errors.isEmpty { throw ClientError.graphql(errors.map(\.message)) }
        guard let d = body.data else { throw ClientError.empty }
        return d
    }

    static let detailBatch = 10
    static let detailConcurrency = 2

    struct DetailFetch: Sendable {
        var prs: [PR] = []
        var failed: Set<String> = []
        var error: (any Error)?
    }

    func fetchPRs(ids: [String]) async -> DetailFetch {
        let batches = stride(from: 0, to: ids.count, by: Self.detailBatch).map {
            Array(ids[$0..<min($0 + Self.detailBatch, ids.count)])
        }
        return await withTaskGroup(of: (batch: [String], result: Result<[PR], any Error>).self) { group in
            var pending = batches[...]
            func next() {
                guard let batch = pending.popFirst() else { return }
                group.addTask {
                    do { return (batch, .success(try await self.details(batch))) }
                    catch { return (batch, .failure(error)) }
                }
            }
            for _ in 0..<Self.detailConcurrency { next() }
            var fetch = DetailFetch()
            for await done in group {
                switch done.result {
                case .success(let prs): fetch.prs += prs
                case .failure(let e):
                    fetch.failed.formUnion(done.batch)
                    fetch.error = fetch.error ?? e
                }
                next()
            }
            return fetch
        }
    }

    private func details(_ ids: [String]) async throws -> [PR] {
        let body: RawDetails = try await send(Query.details(ids))
        if let errors = body.errors, !errors.isEmpty { throw ClientError.graphql(errors.map(\.message)) }
        guard let d = body.data else { throw ClientError.empty }
        return d.nodes.compactMap { PR($0, meuLogin: d.viewer.login) }
    }
}
