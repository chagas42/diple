import Foundation

struct Beat: Sendable, Equatable {
    let updatedAt: Date
    let draft: Bool
    let checks: CheckState
    let approved: Bool

    init(updatedAt: Date, draft: Bool, checks: CheckState, approved: Bool) {
        self.updatedAt = updatedAt
        self.draft = draft
        self.checks = checks
        self.approved = approved
    }

    init(_ pr: PR) {
        self.init(updatedAt: pr.updatedAt, draft: pr.draft, checks: pr.checks, approved: pr.approved)
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

    var all: [Row] { mine + toReview + following }

    func changed(since previous: [String: PR]) -> [String] {
        var seen = Set<String>()
        return all.compactMap { row in
            guard seen.insert(row.id).inserted else { return nil }
            guard let known = previous[row.id], Beat(known) == row.beat else { return row.id }
            return nil
        }
    }

    func queue(known: [String: PR]) -> Queue? {
        func section(_ rows: [Row]) -> [PR]? {
            var out: [PR] = []
            for row in rows {
                guard let pr = known[row.id] else { return nil }
                out.append(pr)
            }
            return out
        }
        guard let m = section(mine), let r = section(toReview), let f = section(following) else { return nil }
        return Queue(viewer: viewer, mine: m, toReview: r, following: f, rateLimitLeft: rateLimitLeft)
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
        let commits: RawPR.RawCommits

        var row: Heartbeat.Row {
            Heartbeat.Row(id: id, beat: Beat(
                updatedAt: updatedAt,
                draft: isDraft,
                checks: CheckState(commits.nodes.compactMap { $0 }.first?.commit.statusCheckRollup?.state),
                approved: reviewDecision == "APPROVED"
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
            rateLimitLeft: sections.compactMap { $0.rateLimit?.remaining }.min() ?? 0
        )
    }

    private func beat(_ search: String) async throws -> RawHeartbeat.Payload {
        let body: RawHeartbeat = try await send(Query.heartbeat(search))
        if let errors = body.errors, !errors.isEmpty { throw ClientError.graphql(errors.map(\.message)) }
        guard let d = body.data else { throw ClientError.empty }
        return d
    }

    func fetchPRs(ids: [String]) async throws -> [PR] {
        guard !ids.isEmpty else { return [] }
        let body: RawDetails = try await send(Query.details(ids))
        if let errors = body.errors, !errors.isEmpty { throw ClientError.graphql(errors.map(\.message)) }
        guard let d = body.data else { throw ClientError.empty }
        return d.nodes.compactMap { PR($0, meuLogin: d.viewer.login) }
    }
}
