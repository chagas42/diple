import Foundation

struct RawResponse: Decodable, Sendable {
    let data: RawData?
    let errors: [GraphQLError]?

    struct RawData: Decodable, Sendable {
        let viewer: RawViewer
        let mine: RawSearch
        let toReview: RawSearch
        let following: RawSearch
        let watched: RawSearch?
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
    let createdAt: Date?
    let isDraft: Bool
    let headRefName: String
    let headRefOid: String?
    let baseRefName: String
    let repository: RawRepo
    var headRepository: RawRepo? = nil
    var maintainerCanModify: Bool? = nil
    var mergeable: String? = nil
    let author: GHActor?
    let reviewDecision: String?
    let reviewRequests: RawRequests?
    let latestReviews: RawReviews?
    let comments: RawComments
    let reviewThreads: RawThreads
    let commits: RawCommits

    struct RawRepo: Decodable, Sendable {
        let nameWithOwner: String
        var viewerPermission: String? = nil
    }
    struct RawRequests: Decodable, Sendable { let nodes: [RawRequest?] }
    struct RawRequest: Decodable, Sendable { let requestedReviewer: RawReviewer? }
    struct RawReviewer: Decodable, Sendable {
        let __typename: String
        let login: String?
    }
    struct RawReviews: Decodable, Sendable { let nodes: [RawReview?] }
    struct RawReview: Decodable, Sendable {
        let state: String
        let author: GHActor?
    }
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
        let isOutdated: Bool?
        let path: String?
        let line: Int?
        let startLine: Int?
        let comments: RawComments
    }
    struct RawCommits: Decodable, Sendable { let nodes: [RawCommitNode?] }
    struct RawCommitNode: Decodable, Sendable { let commit: RawCommit }
    struct RawCommit: Decodable, Sendable { let statusCheckRollup: RawRollup? }
    struct RawRollup: Decodable, Sendable { let state: String }
}

enum CheckState: String, Sendable, Codable {
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

struct PR: Identifiable, Sendable, Equatable, Codable {
    let id: String
    let repo: String
    let number: Int
    let title: String
    let url: URL
    let updatedAt: Date
    let createdAt: Date
    var draft: Bool
    let author: String
    let authorAvatar: URL?
    let isMine: Bool

    let headRef: String
    let head: String?
    let baseRef: String
    let checks: CheckState
    let approved: Bool

    let threads: [ReviewThread]

    let lastComment: HumanComment?

    let askedYou: Bool?

    let approvals: Int?
    let reviewedByOthers: Bool?
    var changesRequested: Int? = nil
    var commentReviews: Int? = nil

    var mergeable: Mergeable? = nil
    var headRepo: String? = nil
    var canPush: Bool? = nil

    var conflicts: Bool { mergeable == .conflicting }

    var asksYouByName: Bool { askedYou == true }
    var hasNoReviews: Bool { reviewedByOthers == false }

    struct ReviewThread: Identifiable, Sendable, Equatable, Codable {
        let id: String
        let path: String
        let line: Int?
        var startLine: Int? = nil
        let diffHunk: String?
        let outdated: Bool
        let comments: [ThreadComment]

        var showsCode: Bool {
            guard let h = diffHunk else { return false }
            return h.split(separator: "\n").contains { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.hasPrefix("@@")
            }
        }

        var location: String {
            let name = path.split(separator: "/").last.map(String.init) ?? path
            return line.map { "\(name):\($0)" } ?? name
        }
    }

    struct ThreadComment: Identifiable, Sendable, Equatable, Codable {
        let id: String
        let author: String
        let at: Date
        let text: String
        let isBot: Bool
    }

    struct HumanComment: Sendable, Equatable, Codable {
        let author: String
        let at: Date
        let excerpt: String

        let location: String?

        let threadId: String?
    }

    init(
        id: String, repo: String, number: Int, title: String, url: URL,
        updatedAt: Date, createdAt: Date, draft: Bool, author: String, authorAvatar: URL?, isMine: Bool,
        headRef: String, baseRef: String, checks: CheckState, approved: Bool,
        threads: [ReviewThread], lastComment: HumanComment?, askedYou: Bool = false, head: String? = nil,
        approvals: Int? = nil, reviewedByOthers: Bool? = nil,
        changesRequested: Int? = nil, commentReviews: Int? = nil
    ) {
        self.id = id
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.draft = draft
        self.author = author
        self.authorAvatar = authorAvatar
        self.isMine = isMine
        self.headRef = headRef
        self.head = head
        self.baseRef = baseRef
        self.checks = checks
        self.approved = approved
        self.threads = threads
        self.lastComment = lastComment
        self.askedYou = askedYou
        self.approvals = approvals
        self.reviewedByOthers = reviewedByOthers
        self.changesRequested = changesRequested
        self.commentReviews = commentReviews
    }

    var key: String { "\(repo)#\(number)" }

    static let writes: Set<String> = ["WRITE", "MAINTAIN", "ADMIN"]

    static func canPush(head: String?, base: String?, maintainerCanModify: Bool?) -> Bool? {
        guard head != nil || base != nil else { return nil }
        if let head, writes.contains(head) { return true }
        return maintainerCanModify == true && base.map(writes.contains) == true
    }

    static let countedReviews: Set<String> = ["APPROVED", "CHANGES_REQUESTED", "COMMENTED"]

    static func counted(_ raw: RawPR.RawReviews?, author: String?) -> [String]? {
        raw.map { r in
            r.nodes.compactMap { $0 }.filter { review in
                guard let a = review.author, !a.isBot, a.login != author else { return false }
                return countedReviews.contains(review.state)
            }.map(\.state)
        }
    }

    var revision: String { head ?? "\(updatedAt.timeIntervalSince1970)" }

    init?(_ c: RawPR?, meuLogin: String) {
        guard let c else { return nil }
        id = c.id
        repo = c.repository.nameWithOwner
        number = c.number
        title = c.title
        url = c.url
        updatedAt = c.updatedAt
        createdAt = c.createdAt ?? c.updatedAt
        draft = c.isDraft
        author = c.author?.login ?? "?"
        authorAvatar = c.author?.avatarUrl
        isMine = c.author?.login == meuLogin
        headRef = c.headRefName
        head = c.headRefOid
        baseRef = c.baseRefName
        mergeable = c.mergeable.map(Mergeable.init(github:))
        headRepo = c.headRepository?.nameWithOwner
        canPush = Self.canPush(head: c.headRepository?.viewerPermission, base: c.repository.viewerPermission,
                               maintainerCanModify: c.maintainerCanModify)
        checks = CheckState(c.commits.nodes.compactMap { $0 }.first?.commit.statusCheckRollup?.state)
        approved = c.reviewDecision == "APPROVED"
        let reviews = Self.counted(c.latestReviews, author: c.author?.login)
        approvals = reviews.map { $0.filter { $0 == "APPROVED" }.count }
        reviewedByOthers = reviews.map { !$0.isEmpty }
        changesRequested = reviews.map { $0.filter { $0 == "CHANGES_REQUESTED" }.count }
        commentReviews = reviews.map { $0.filter { $0 == "COMMENTED" }.count }
        askedYou = c.reviewRequests?.nodes.contains {
            $0?.requestedReviewer?.__typename == "User" && $0?.requestedReviewer?.login == meuLogin
        } ?? false

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
                    startLine: t.startLine,
                    diffHunk: t.comments.nodes.compactMap { $0?.diffHunk }.first,
                    outdated: t.isOutdated ?? false,
                    comments: falas
                )
            }
    }
}

struct Queue: Sendable, Equatable, Codable {
    var viewer: String = ""
    var mine: [PR] = []
    var toReview: [PR] = []
    var following: [PR] = []
    var watched: [PR] = []
    var rateLimitLeft: Int = 0
    var rateLimitResetAt: Date? = nil

    var all: [PR] { mine + toReview + following + watched }

    enum Section: String, CaseIterable, Sendable {
        case mine, toReview, following, watched

        var title: String {
            switch self {
            case .mine:      "Your PRs"
            case .toReview:  "Reviewing"
            case .following: "Following"
            case .watched:   "Watching"
            }
        }
    }

    subscript(section: Section) -> [PR] {
        get {
            switch section {
            case .mine:      mine
            case .toReview:  toReview
            case .following: following
            case .watched:   watched
            }
        }
        set {
            switch section {
            case .mine:      mine = newValue
            case .toReview:  toReview = newValue
            case .following: following = newValue
            case .watched:   watched = newValue
            }
        }
    }
}

struct RawSectionResponse: Decodable, Sendable {
    let data: RawData?
    let errors: [GraphQLError]?

    struct RawData: Decodable, Sendable {
        let viewer: RawResponse.RawViewer
        let mine: RawResponse.RawSearch?
        let toReview: RawResponse.RawSearch?
        let following: RawResponse.RawSearch?
        let watched: RawResponse.RawSearch?
        let rateLimit: RawResponse.RawRateLimit?

        subscript(section: Queue.Section) -> RawResponse.RawSearch? {
            switch section {
            case .mine:      mine
            case .toReview:  toReview
            case .following: following
            case .watched:   watched
            }
        }
    }
}

enum Mergeable: String, Codable, Sendable, Equatable {
    case mergeable, conflicting, unknown

    init(github: String) {
        self = Mergeable(rawValue: github.lowercased()) ?? .unknown
    }
}
