import Foundation

struct ReviewContext: Sendable, Equatable {
    struct Note: Sendable, Equatable {
        let id: String
        let author: String
        let isBot: Bool
        let body: String
        let at: String
    }

    struct Thread: Sendable, Equatable, Identifiable {
        let id: String
        let path: String
        let line: Int?
        let isResolved: Bool
        let isOutdated: Bool
        let url: URL?
        let comments: [Note]

        var location: String {
            let name = path.split(separator: "/").last.map(String.init) ?? path
            return line.map { "\(name):\($0)" } ?? name
        }
    }

    struct Review: Sendable, Equatable {
        let id: String
        let author: String
        let isBot: Bool
        let state: String
        let body: String
    }

    var base = ""
    var head = ""
    var body = ""
    var author = ""
    var threads: [Thread] = []
    var conversation: [Note] = []
    var reviews: [Review] = []

    var openThreads: Int { threads.filter { !$0.isResolved }.count }
}

extension GitHubClient {
    func reviewContext(repo: String, pr: Int) async throws -> ReviewContext {
        let parts = repo.split(separator: "/").map(String.init)
        guard parts.count == 2 else { throw ClientError.graphql(["not a repository: \(repo)"]) }

        let json = try await raw("""
        { repository(owner: "\(parts[0])", name: "\(parts[1])") {
            pullRequest(number: \(pr)) {
              baseRefOid
              headRefOid
              body
              author { login __typename }
              reviewThreads(first: 100) {
                nodes {
                  id isResolved isOutdated path line originalLine
                  comments(first: 30) {
                    nodes { id author { login __typename } bodyText createdAt url }
                  }
                }
              }
              comments(first: 100) {
                nodes { id author { login __typename } bodyText createdAt }
              }
              reviews(first: 50) {
                nodes { id author { login __typename } state bodyText }
              }
            }
        } }
        """)

        let data = json["data"] as? [String: Any]
        let repository = data?["repository"] as? [String: Any]
        guard let pull = repository?["pullRequest"] as? [String: Any],
              let base = pull["baseRefOid"] as? String, !base.isEmpty else {
            throw ClientError.graphql(["PR #\(pr) of \(repo) was not found"])
        }

        func actor(_ o: Any?) -> (String, Bool) {
            let a = o as? [String: Any]
            let login = (a?["login"] as? String) ?? "ghost"
            return (login, GHActor.isBot(login: login, typename: (a?["__typename"] as? String) ?? ""))
        }
        func nodes(_ key: String, in o: [String: Any]?) -> [[String: Any]] {
            ((o?[key] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        }
        func note(_ n: [String: Any]) -> ReviewContext.Note {
            let (login, bot) = actor(n["author"])
            return ReviewContext.Note(
                id: (n["id"] as? String) ?? UUID().uuidString,
                author: login, isBot: bot,
                body: String(((n["bodyText"] as? String) ?? "").prefix(2000)),
                at: (n["createdAt"] as? String) ?? ""
            )
        }

        var ctx = ReviewContext()
        ctx.base = base
        ctx.head = (pull["headRefOid"] as? String) ?? ""
        ctx.body = String(((pull["body"] as? String) ?? "").prefix(12_000))
        ctx.author = actor(pull["author"]).0

        ctx.threads = nodes("reviewThreads", in: pull).compactMap { t in
            guard let id = t["id"] as? String else { return nil }
            let comments = nodes("comments", in: t)
            return ReviewContext.Thread(
                id: id,
                path: (t["path"] as? String) ?? "",
                line: (t["line"] as? Int) ?? (t["originalLine"] as? Int),
                isResolved: (t["isResolved"] as? Bool) ?? false,
                isOutdated: (t["isOutdated"] as? Bool) ?? false,
                url: (comments.first?["url"] as? String).flatMap(URL.init(string:)),
                comments: comments.map(note)
            )
        }
        ctx.conversation = nodes("comments", in: pull).map(note)
        ctx.reviews = nodes("reviews", in: pull).compactMap { r in
            let body = (r["bodyText"] as? String) ?? ""
            guard !body.isEmpty else { return nil }
            let (login, bot) = actor(r["author"])
            return ReviewContext.Review(
                id: (r["id"] as? String) ?? UUID().uuidString,
                author: login, isBot: bot,
                state: (r["state"] as? String) ?? "",
                body: String(body.prefix(2000))
            )
        }
        return ctx
    }
}
