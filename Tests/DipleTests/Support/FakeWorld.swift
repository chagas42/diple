import Foundation

struct FakeComment {
    var author: String
    var isBot = false
    var at: Date
    var body: String
    var hunk: String?
}

struct FakeThread {
    var id: String
    var path = "src/orders/service.ts"
    var line: Int? = 42
    var resolved = false
    var comments: [FakeComment]
}

struct FakePR {
    var id: String
    var repo: String
    var number: Int
    var title: String
    var author: String
    var updatedAt: Date
    var draft = false
    var checks: String? = "SUCCESS"
    var decision: String? = nil
    var conversation: [FakeComment] = []
    var threads: [FakeThread] = []
}

struct FakeWorld {
    var viewer = "you"
    var mine: [FakePR] = []
    var toReview: [FakePR] = []
    var following: [FakePR] = []
    var rateLimit = 4999

    static let epoch = Date(timeIntervalSince1970: 1_790_000_000)

    static func text(_ n: Int, seed: Int) -> String {
        let words = ["order", "retry", "ticket", "account", "handler", "queue", "timeout", "cache", "invoice", "payload"]
        var out = ""
        var i = seed
        while out.count < n {
            out += words[i % words.count] + " "
            i += 7
        }
        return String(out.prefix(n))
    }

    static func hunk(lines: Int, seed: Int) -> String {
        var out = "@@ -10,\(lines) +10,\(lines + 2) @@\n"
        for i in 0..<lines {
            let mark = i % 5 == 0 ? "+" : (i % 7 == 0 ? "-" : " ")
            out += "\(mark)  const \(text(12, seed: seed + i).replacingOccurrences(of: " ", with: "_")) = await load(id)\n"
        }
        return out
    }

    static func pr(_ index: Int, author: String, viewer: String) -> FakePR {
        let at = epoch.addingTimeInterval(Double(-index * 600))
        let bots = (0..<3).map { k in
            FakeComment(author: "coderabbitai", isBot: true, at: at.addingTimeInterval(Double(-k * 60)),
                        body: text(2000, seed: index * 10 + k))
        }
        let human = FakeComment(author: "reviewer\(index % 5)", at: at.addingTimeInterval(-300),
                                body: text(200, seed: index))
        var threads: [FakeThread] = []
        for t in 0..<3 {
            threads.append(thread(index, t, author: author, at: at))
        }
        return FakePR(
            id: "PR_\(index)",
            repo: "acme/repo\(index % 4)",
            number: 100 + index,
            title: "Change \(index): \(text(40, seed: index))",
            author: author,
            updatedAt: at,
            conversation: [human] + bots,
            threads: threads
        )
    }

    static func thread(_ index: Int, _ t: Int, author: String, at: Date) -> FakeThread {
        var comments: [FakeComment] = []
        for c in 0..<2 {
            let who: String = c == 0 ? "reviewer\(t)" : author
            let offset = Double(-900 - t * 60 - c * 30)
            let body: String = text(300, seed: index * 100 + t * 10 + c)
            let diff: String = hunk(lines: 8, seed: index + t)
            comments.append(FakeComment(author: who, at: at.addingTimeInterval(offset), body: body, hunk: diff))
        }
        return FakeThread(id: "T_\(index)_\(t)", path: "src/module\(t)/file\(index).ts", line: 10 + t, comments: comments)
    }

    static func realistic() -> FakeWorld {
        var w = FakeWorld()
        w.mine = (0..<14).map { pr($0, author: w.viewer, viewer: w.viewer) }
        w.toReview = (14..<18).map { pr($0, author: "teammate\($0)", viewer: w.viewer) }
        w.following = (18..<36).map { pr($0, author: "teammate\($0)", viewer: w.viewer) }
        return w
    }

    var all: [FakePR] { mine + toReview + following }

    mutating func update(_ id: String, _ change: (inout FakePR) -> Void) {
        for i in mine.indices where mine[i].id == id { change(&mine[i]) }
        for i in toReview.indices where toReview[i].id == id { change(&toReview[i]) }
        for i in following.indices where following[i].id == id { change(&following[i]) }
    }

    func queueResponse() -> Data {
        let data: [String: Any] = [
            "viewer": ["login": viewer],
            "mine": ["nodes": mine.map(Self.json)],
            "toReview": ["nodes": toReview.map(Self.json)],
            "following": ["nodes": following.map(Self.json)],
            "rateLimit": ["remaining": rateLimit, "resetAt": Self.iso(Self.epoch.addingTimeInterval(3600))],
        ]
        return try! JSONSerialization.data(withJSONObject: ["data": data])
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: d)
    }

    static func actor(_ login: String, bot: Bool) -> [String: Any] {
        ["login": login, "__typename": bot ? "Bot" : "User", "avatarUrl": "https://example.invalid/\(login).png"]
    }

    static func comment(_ c: FakeComment) -> [String: Any] {
        var o: [String: Any] = [
            "author": actor(c.author, bot: c.isBot),
            "createdAt": iso(c.at),
            "bodyText": c.body,
        ]
        if let h = c.hunk { o["diffHunk"] = h }
        return o
    }

    static func json(_ p: FakePR) -> [String: Any] {
        [
            "id": p.id,
            "number": p.number,
            "title": p.title,
            "url": "https://github.com/\(p.repo)/pull/\(p.number)",
            "updatedAt": iso(p.updatedAt),
            "isDraft": p.draft,
            "headRefName": "feature/\(p.number)",
            "baseRefName": "main",
            "repository": ["nameWithOwner": p.repo],
            "author": actor(p.author, bot: false),
            "reviewDecision": p.decision.map { $0 as Any } ?? NSNull(),
            "comments": ["nodes": p.conversation.map(comment)],
            "reviewThreads": ["nodes": p.threads.map { t in
                [
                    "id": t.id,
                    "isResolved": t.resolved,
                    "path": t.path,
                    "line": t.line.map { $0 as Any } ?? NSNull(),
                    "comments": ["nodes": t.comments.map(comment)],
                ] as [String: Any]
            }],
            "commits": ["nodes": [["commit": ["statusCheckRollup": p.checks.map { ["state": $0] as Any } ?? NSNull()]]]],
        ]
    }
}
