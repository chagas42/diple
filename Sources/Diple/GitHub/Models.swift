import Foundation

struct RawResponse: Decodable, Sendable {
    let data: RawData?
    let errors: [GraphQLError]?

    struct RawData: Decodable, Sendable {
        let viewer: RawViewer
        let mine: RawSearch
        let toReview: RawSearch
        let following: RawSearch
        let rateLimit: RawRateLimit?
    }

    struct RawViewer: Decodable, Sendable { let login: String }

    struct RawSearch: Decodable, Sendable {
        let nodes: [RawPR?]
    }

    struct RawRateLimit: Decodable, Sendable {
        let remaining: Int
        let resetAt: Date
    }
}

struct GraphQLError: Decodable, Sendable {
    let message: String
}

struct GHActor: Decodable, Sendable {
    let login: String
    let __typename: String
    let avatarUrl: URL?

    var isBot: Bool { GHActor.isBot(login: login, typename: __typename) }

    static func isBot(login: String, typename: String) -> Bool {
        typename == "Bot" || login.hasSuffix("[bot]") || knownBots.contains(login)
    }

    private static let knownBots: Set<String> = [
        "github-actions", "coderabbitai", "dependabot", "renovate",
        "codecov", "sonarcloud", "vercel", "sentry-io",
    ]
}

struct RawPR: Decodable, Sendable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let updatedAt: Date
    let isDraft: Bool
    let headRefName: String
    let baseRefName: String
    let repository: RawRepo
    let author: GHActor?
    let reviewDecision: String?
    let comments: RawComments
    let reviewThreads: RawThreads
    let commits: RawCommits

    struct RawRepo: Decodable, Sendable { let nameWithOwner: String }
    struct RawComments: Decodable, Sendable { let nodes: [RawComment?] }
    struct RawComment: Decodable, Sendable {
        let author: GHActor?
        let createdAt: Date
        let bodyText: String

        let diffHunk: String?
    }
    struct RawThreads: Decodable, Sendable { let nodes: [RawReviewThread?] }
    struct RawReviewThread: Decodable, Sendable {
        let id: String
        let isResolved: Bool
        let path: String?
        let line: Int?
        let comments: RawComments
    }
    struct RawCommits: Decodable, Sendable { let nodes: [RawCommitNode?] }
    struct RawCommitNode: Decodable, Sendable { let commit: RawCommit }
    struct RawCommit: Decodable, Sendable { let statusCheckRollup: RawRollup? }
    struct RawRollup: Decodable, Sendable { let state: String }
}

enum CheckState: String, Sendable {
    case passing, failing, running, none

    init(_ raw: String?) {
        switch raw {
        case "SUCCESS":  self = .passing
        case "FAILURE", "ERROR": self = .failing
        case "PENDING", "EXPECTED": self = .running
        default: self = .none
        }
    }
}

struct PR: Identifiable, Sendable, Equatable {
    let id: String
    let repo: String
    let number: Int
    let title: String
    let url: URL
    let updatedAt: Date
    let draft: Bool
    let author: String
    let authorAvatar: URL?
    let isMine: Bool

    let headRef: String
    let baseRef: String
    let checks: CheckState
    let approved: Bool

    let threads: [ReviewThread]

    let lastComment: HumanComment?

    struct ReviewThread: Identifiable, Sendable, Equatable {
        let id: String
        let path: String
        let line: Int?
        let diffHunk: String?
        let comments: [ThreadComment]

        var location: String {
            let name = path.split(separator: "/").last.map(String.init) ?? path
            return line.map { "\(name):\($0)" } ?? name
        }
    }

    struct ThreadComment: Identifiable, Sendable, Equatable {
        let id: String
        let author: String
        let at: Date
        let text: String
        let isBot: Bool
    }

    struct HumanComment: Sendable, Equatable {
        let author: String
        let at: Date
        let excerpt: String

        let location: String?

        let threadId: String?
    }

    init(
        id: String, repo: String, number: Int, title: String, url: URL,
        updatedAt: Date, draft: Bool, author: String, authorAvatar: URL?, isMine: Bool,
        headRef: String, baseRef: String, checks: CheckState, approved: Bool,
        threads: [ReviewThread], lastComment: HumanComment?
    ) {
        self.id = id
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.updatedAt = updatedAt
        self.draft = draft
        self.author = author
        self.authorAvatar = authorAvatar
        self.isMine = isMine
        self.headRef = headRef
        self.baseRef = baseRef
        self.checks = checks
        self.approved = approved
        self.threads = threads
        self.lastComment = lastComment
    }

    var key: String { "\(repo)#\(number)" }

    init?(_ c: RawPR?, meuLogin: String) {
        guard let c else { return nil }
        id = c.id
        repo = c.repository.nameWithOwner
        number = c.number
        title = c.title
        url = c.url
        updatedAt = c.updatedAt
        draft = c.isDraft
        author = c.author?.login ?? "?"
        authorAvatar = c.author?.avatarUrl
        isMine = c.author?.login == meuLogin
        headRef = c.headRefName
        baseRef = c.baseRefName
        checks = CheckState(c.commits.nodes.compactMap { $0 }.first?.commit.statusCheckRollup?.state)
        approved = c.reviewDecision == "APPROVED"

        func humano(_ com: RawPR.RawComment) -> Bool {
            guard let a = com.author else { return false }
            return !a.isBot && a.login != meuLogin
        }
        func clear(_ t: String) -> String {
            String(t.prefix(180)).replacingOccurrences(of: "\n", with: " ")
        }

        var candidatos: [HumanComment] = c.comments.nodes
            .compactMap { $0 }
            .filter(humano)
            .map { .init(author: $0.author?.login ?? "?", at: $0.createdAt,
                         excerpt: clear($0.bodyText), location: nil, threadId: nil) }

        for t in c.reviewThreads.nodes.compactMap({ $0 }) where !t.isResolved {
            let location = t.path.map { p in
                let path = p.split(separator: "/").last.map(String.init) ?? p
                return t.line.map { "\(path):\($0)" } ?? path
            }
            candidatos += t.comments.nodes
                .compactMap { $0 }
                .filter(humano)
                .map { .init(author: $0.author?.login ?? "?", at: $0.createdAt,
                             excerpt: clear($0.bodyText), location: location, threadId: t.id) }
        }

        lastComment = candidatos.max { $0.at < $1.at }

        threads = c.reviewThreads.nodes.compactMap { $0 }
            .filter { !$0.isResolved }
            .compactMap { t in
                let falas = t.comments.nodes.compactMap { $0 }.map { com in
                    ThreadComment(
                        id: "\(t.id)/\(com.createdAt.timeIntervalSince1970)",
                        author: com.author?.login ?? "?",
                        at: com.createdAt,
                        text: com.bodyText,
                        isBot: com.author?.isBot ?? false
                    )
                }
                guard falas.contains(where: { !$0.isBot }) else { return nil }
                return ReviewThread(
                    id: t.id,
                    path: t.path ?? "?",
                    line: t.line,
                    diffHunk: t.comments.nodes.compactMap { $0?.diffHunk }.first,
                    comments: falas
                )
            }
    }
}

struct Queue: Sendable, Equatable {
    var viewer: String = ""
    var mine: [PR] = []
    var toReview: [PR] = []
    var following: [PR] = []
    var rateLimitLeft: Int = 0

    var all: [PR] { mine + toReview + following }
}
