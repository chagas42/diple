import Foundation

struct ChangeFeed: Sendable, Equatable {
    struct Reply: Sendable, Equatable {
        var status: Int
        var lastModified: String?
        var etag: String?
        var pollInterval: TimeInterval?
        var body = Data()
    }

    struct Thread: Decodable, Sendable, Equatable {
        struct Subject: Decodable, Sendable, Equatable { var type: String }
        struct Repository: Decodable, Sendable, Equatable { var full_name: String }

        var reason: String
        var updated_at: Date
        var subject: Subject
        var repository: Repository

        var repo: String { repository.full_name }
    }

    enum Verdict: Sendable, Equatable {
        case unchanged, quiet, wake, off
    }

    static let path = "notifications?per_page=5"
    static let minimumInterval: TimeInterval = 60
    static let involvingReasons: Set<String> = [
        "review_requested", "author", "mention", "team_mention", "assign", "comment", "state_change",
    ]

    private(set) var lastModified: String?
    private(set) var etag: String?
    private(set) var seen: Date?
    private(set) var interval = minimumInterval
    private(set) var isOff = false

    var conditionalHeaders: [String: String] {
        var headers: [String: String] = [:]
        if let lastModified { headers["If-Modified-Since"] = lastModified }
        if let etag { headers["If-None-Match"] = etag }
        return headers
    }

    mutating func absorb(_ reply: Reply, watching: Set<String>, muted: Set<String> = []) -> Verdict {
        if let poll = reply.pollInterval { interval = max(poll, Self.minimumInterval) }
        switch reply.status {
        case 304:
            return .unchanged
        case 401, 403, 404:
            isOff = true
            return .off
        case 200..<300:
            lastModified = reply.lastModified ?? lastModified
            etag = reply.etag ?? etag
            guard let threads = Self.threads(in: reply.body) else { return .quiet }
            let previous = seen
            seen = ([previous].compactMap { $0 } + threads.map(\.updated_at)).max()
            guard let previous else { return .quiet }
            let moved = threads.contains { thread in
                thread.updated_at > previous
                    && thread.subject.type == "PullRequest"
                    && !muted.contains(thread.repo)
                    && (watching.contains(thread.repo) || Self.involvingReasons.contains(thread.reason))
            }
            return moved ? .wake : .quiet
        default:
            return .quiet
        }
    }

    static func threads(in body: Data) -> [Thread]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Thread].self, from: body)
    }
}
