import Foundation

enum ClientError: LocalizedError {
    case http(Int, attempts: Int = 1)
    case graphql([String])
    case empty

    var errorDescription: String? {
        switch self {
        case .http(let c, _):   "GitHub respondeu HTTP \(c)"
        case .graphql(let m):   m.joined(separator: " · ")
        case .empty:            "GitHub answered with no data"
        }
    }
}

struct GitHubClient: Sendable {
    private let endpoint = URL(string: "https://api.github.com/graphql")!
    private let transport: any Transport
    private let tokens: any TokenSource
    private let metrics: Metrics
    private let telemetry: Telemetry
    private let retryDelays: [Duration]

    static let transient: Set<Int> = [502, 503, 504]

    init(
        transport: any Transport = URLSessionTransport(),
        tokens: any TokenSource = CachedTokenSource.shared,
        metrics: Metrics = .shared,
        telemetry: Telemetry = .shared,
        retryDelays: [Duration] = [.seconds(1), .seconds(3)]
    ) {
        self.transport = transport
        self.tokens = tokens
        self.metrics = metrics
        self.telemetry = telemetry
        self.retryDelays = retryDelays
    }

    func post(_ query: String, variables: [String: String]? = nil) async throws -> Data {
        let body = try variables.map {
            try JSONSerialization.data(withJSONObject: ["query": query, "variables": $0])
        } ?? JSONEncoder().encode(["query": query])

        let delays = Self.isMutation(query) ? [] : retryDelays
        let request = TelemetryEvent.GitHubRequest(query: query)
        var attempts = 1
        var status = 0
        while true {
            do {
                let payload = try await authorized(body)
                if attempts > 1 {
                    telemetry.capture(.githubRetry(outcome: .recovered, status: status, request: request, attempts: attempts))
                }
                return payload
            } catch ClientError.http(let code, _) where Self.transient.contains(code) {
                status = code
                guard attempts <= delays.count else {
                    if attempts > 1 {
                        telemetry.capture(.githubRetry(outcome: .failed, status: code, request: request, attempts: attempts))
                    }
                    throw ClientError.http(code, attempts: attempts)
                }
                try await Task.sleep(for: delays[attempts - 1] * Double.random(in: 0.7...1.3))
                attempts += 1
            }
        }
    }

    static func isMutation(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("mutation")
    }

    private func authorized(_ body: Data) async throws -> Data {
        do {
            return try await attempt(body)
        } catch ClientError.http(401, _) {
            await tokens.invalidate()
            return try await attempt(body)
        }
    }

    private func attempt(_ body: Data) async throws -> Data {
        let token = try await tokens.current()

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Diple/0.1", forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        req.timeoutInterval = 20

        let (payload, response) = try await metrics.measure(.request) {
            try await transport.send(req)
        }
        metrics.count(.requests)
        metrics.count(.bytesOut, by: body.count)
        metrics.count(.bytesIn, by: payload.count)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }
        return payload
    }

    func rest(_ path: String) async throws -> Data {
        func once() async throws -> Data {
            let token = try await tokens.current()
            var req = URLRequest(url: URL(string: "https://api.github.com/\(path)")!)
            req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("Diple/0.1", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 20
            let (payload, response) = try await metrics.measure(.request) {
                try await transport.send(req)
            }
            metrics.count(.requests)
            metrics.count(.bytesIn, by: payload.count)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ClientError.http(http.statusCode)
            }
            return payload
        }
        do {
            return try await once()
        } catch ClientError.http(401, _) {
            await tokens.invalidate()
            return try await once()
        }
    }

    func openPR(repo: String, head: String, etag: String?) async throws -> PullLookup.Result? {
        let token = try await tokens.current()
        var req = URLRequest(url: URL(string: "https://api.github.com/\(PullLookup.path(repo: repo, head: head))")!)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Diple/0.1", forHTTPHeaderField: "User-Agent")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        req.timeoutInterval = 20
        let (payload, response) = try await transport.send(req)
        metrics.count(.requests)
        metrics.count(.bytesIn, by: payload.count)
        guard let http = response as? HTTPURLResponse else { return nil }
        return PullLookup.result(status: http.statusCode, body: payload, etag: http.value(forHTTPHeaderField: "ETag"))
    }

    func notifications(_ feed: ChangeFeed) async throws -> ChangeFeed.Reply {
        func once() async throws -> ChangeFeed.Reply {
            let token = try await tokens.current()
            var req = URLRequest(url: URL(string: "https://api.github.com/\(ChangeFeed.path)")!)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("Diple/0.1", forHTTPHeaderField: "User-Agent")
            for (field, value) in feed.conditionalHeaders { req.setValue(value, forHTTPHeaderField: field) }
            req.timeoutInterval = 20
            let (payload, response) = try await metrics.measure(.request) {
                try await transport.send(req)
            }
            metrics.count(.requests)
            metrics.count(.bytesIn, by: payload.count)
            let http = response as? HTTPURLResponse
            return ChangeFeed.Reply(
                status: http?.statusCode ?? 0,
                lastModified: http?.value(forHTTPHeaderField: "Last-Modified"),
                etag: http?.value(forHTTPHeaderField: "ETag"),
                pollInterval: http?.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(TimeInterval.init),
                body: payload
            )
        }
        let reply = try await once()
        guard reply.status == 401 else { return reply }
        await tokens.invalidate()
        return try await once()
    }

    func requiredApprovals(repo: String, branch: String) async throws -> RequiredApprovals {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return RequiredApprovals(count: nil) }
        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
        async let rules = try? rest("repos/\(repo)/rules/branches/\(encoded)")
        let classic = try? await post("""
        query($owner: String!, $name: String!, $ref: String!) {
          repository(owner: $owner, name: $name) {
            viewerPermission
            ref(qualifiedName: $ref) { branchProtectionRule { requiredApprovingReviewCount } }
          }
        }
        """, variables: ["owner": parts[0], "name": parts[1], "ref": "refs/heads/\(branch)"])
        return RequiredApprovals(rules: await rules, classic: classic ?? Data())
    }

    func send<T: Decodable & Sendable>(_ query: String) async throws -> T {
        let payload = try await post(query)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(T.self, from: payload)
    }

    struct SectionFetch: Sendable {
        var viewer: String?
        var sections: [Queue.Section: [PR]] = [:]
        var failures: [Queue.Section: any Error] = [:]
        var rateLimitLeft: Int?
        var rateLimitResetAt: Date?
    }

    func fetchSections(watching: Set<String> = []) async -> SectionFetch {
        let searches = Query.searches(watching: watching)
        let results = await withTaskGroup(of: (Queue.Section, Result<RawSectionResponse.RawData, any Error>).self) { group in
            for (section, search) in searches {
                group.addTask {
                    do { return (section, .success(try await self.section(section, search: search))) }
                    catch { return (section, .failure(error)) }
                }
            }
            var out: [(Queue.Section, Result<RawSectionResponse.RawData, any Error>)] = []
            for await r in group { out.append(r) }
            return out
        }
        var fetch = SectionFetch()
        for (section, result) in results {
            switch result {
            case .success(let d):
                let viewer = d.viewer.login
                fetch.viewer = viewer
                fetch.sections[section] = (d[section]?.nodes ?? []).compactMap { PR($0, meuLogin: viewer) }
                if let r = d.rateLimit {
                    fetch.rateLimitLeft = min(fetch.rateLimitLeft ?? r.remaining, r.remaining)
                    fetch.rateLimitResetAt = max(fetch.rateLimitResetAt ?? r.resetAt, r.resetAt)
                }
            case .failure(let e):
                fetch.failures[section] = e
            }
        }
        return fetch
    }

    private func section(_ section: Queue.Section, search: String) async throws -> RawSectionResponse.RawData {
        let body: RawSectionResponse = try await send(Query.queueSection(section, search: search))
        if let errors = body.errors, !errors.isEmpty { throw ClientError.graphql(errors.map(\.message)) }
        guard let d = body.data else { throw ClientError.empty }
        return d
    }

    func fetchQueue(watching: Set<String> = []) async throws -> Queue {
        let fetch = await fetchSections(watching: watching)
        if let failure = Queue.Section.allCases.compactMap({ fetch.failures[$0] }).first { throw failure }
        var queue = Queue(
            viewer: fetch.viewer ?? "",
            rateLimitLeft: fetch.rateLimitLeft ?? 0,
            rateLimitResetAt: fetch.rateLimitResetAt
        )
        for (section, prs) in fetch.sections { queue[section] = prs }
        return queue
    }
}

extension GitHubClient {
    private func escaped(_ v: String) -> String {
        v.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "")
    }

    func startThread(prId: String, path: String, line: Int?, body: String) async throws {
        let place = line.map { "line: \($0), side: RIGHT, subjectType: LINE," }
                    ?? "subjectType: FILE,"
        let query = """
        mutation {
          addPullRequestReviewThread(input: {
            pullRequestId: "\(prId)",
            path: "\(escaped(path))",
            \(place)
            body: "\(escaped(body))"
          }) { thread { id } }
        }
        """
        struct Added: Decodable, Sendable { let errors: [GraphQLError]? }
        let since = Date().addingTimeInterval(-Self.clockSlack)
        try await landing(check: { try await self.pendingComment(prId: prId, path: path, since: since) }) {
            let added: Added = try await self.send(query)
            if let e = added.errors, !e.isEmpty { throw ClientError.graphql(e.map(\.message)) }
        }
        try await landing(check: { try await self.submittedReview(prId: prId, since: since) }) {
            try await self.submitPendingReview(prId: prId)
        }
    }

    private func submitPendingReview(prId: String) async throws {
        let query = """
        mutation {
          submitPullRequestReview(input: {
            pullRequestId: "\(prId)",
            event: COMMENT
          }) { pullRequestReview { id state } }
        }
        """
        struct Submitted: Decodable, Sendable { let errors: [GraphQLError]? }
        let r: Submitted = try await send(query)
        if let e = r.errors, !e.isEmpty { throw ClientError.graphql(e.map(\.message)) }
    }

    func reply(threadId: String, body: String) async throws {
        let since = Date().addingTimeInterval(-Self.clockSlack)
        try await landing(check: { try await self.repliedLast(threadId: threadId, since: since) }) {
            try await self.sendReply(threadId: threadId, body: body)
        }
    }

    private func sendReply(threadId: String, body: String) async throws {
        _ = try await mutate(
            """
            mutation($t: ID!, $b: String!) {
              addPullRequestReviewThreadReply(
                input: { pullRequestReviewThreadId: $t, body: $b }
              ) { comment { id } }
            }
            """,
            ["t": threadId, "b": body]
        )
    }

    func comment(prId: String, body: String) async throws {
        let since = Date().addingTimeInterval(-Self.clockSlack)
        try await landing(check: { try await self.commentedLast(prId: prId, since: since) }) {
            _ = try await self.mutate(
                """
                mutation($s: ID!, $b: String!) {
                  addComment(input: { subjectId: $s, body: $b }) { commentEdge { node { id } } }
                }
                """,
                ["s": prId, "b": body]
            )
        }
    }

    func commentedLast(prId: String, since: Date) async throws -> Bool {
        let d = try await check("""
        node(id: "\(escaped(prId))") { ... on PullRequest {
          comments(last: 1) { nodes { author { login } createdAt } }
        } }
        """)
        let last = (((d["node"] as? [String: Any])?["comments"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last
        let author = (last?["author"] as? [String: Any])?["login"] as? String
        guard let me = Self.login(d), author == me, let at = Self.date(last?["createdAt"]) else { return false }
        return at >= since
    }

    static func isOffDiff(_ error: Error) -> Bool {
        guard case ClientError.graphql(let messages) = error else { return false }
        let text = messages.joined(separator: " ").lowercased()
        return ["could not be resolved", "part of the diff", "line must", "position"].contains { text.contains($0) }
    }

    func resolve(threadId: String) async throws {
        try await landing(check: { try await self.isResolved(threadId: threadId) }) {
            try await self.sendResolve(threadId: threadId)
        }
    }

    private func sendResolve(threadId: String) async throws {
        _ = try await mutate(
            """
            mutation($t: ID!) {
              resolveReviewThread(input: { threadId: $t }) { thread { id } }
            }
            """,
            ["t": threadId]
        )
    }

    func markReadyForReview(prId: String) async throws {
        try await landing(check: { try await self.isReady(prId: prId) }) {
            _ = try await self.mutate(
                """
                mutation($p: ID!) {
                  markPullRequestReadyForReview(input: { pullRequestId: $p }) { pullRequest { id isDraft } }
                }
                """,
                ["p": prId]
            )
        }
    }

    static let clockSlack: TimeInterval = 60

    static func isUncertain(_ error: Error) -> Bool {
        if case ClientError.http(let code, _) = error { return transient.contains(code) }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain
            && [NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(ns.code)
    }

    private func landing(check: () async throws -> Bool, _ mutation: () async throws -> Void) async throws {
        do {
            try await mutation()
        } catch where Self.isUncertain(error) {
            let status = (error as? ClientError).flatMap { if case .http(let c, _) = $0 { c } else { nil } } ?? 0
            let landed = (try? await check()) ?? false
            telemetry.capture(.githubRetry(outcome: landed ? .landed : .lost, status: status, request: .mutation, attempts: 1))
            if !landed { throw error }
        }
    }

    private func check(_ body: String) async throws -> [String: Any] {
        let json = try await raw("query MutationCheck { viewer { login } \(body) }")
        return json["data"] as? [String: Any] ?? [:]
    }

    private static func date(_ v: Any?) -> Date? {
        (v as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    private static func login(_ data: [String: Any]) -> String? {
        (data["viewer"] as? [String: Any])?["login"] as? String
    }

    func repliedLast(threadId: String, since: Date) async throws -> Bool {
        let d = try await check("""
        node(id: "\(escaped(threadId))") { ... on PullRequestReviewThread {
          comments(last: 1) { nodes { author { login } createdAt } }
        } }
        """)
        let last = (((d["node"] as? [String: Any])?["comments"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last
        let author = (last?["author"] as? [String: Any])?["login"] as? String
        guard let me = Self.login(d), author == me, let at = Self.date(last?["createdAt"]) else { return false }
        return at >= since
    }

    func isResolved(threadId: String) async throws -> Bool {
        let d = try await check("""
        node(id: "\(escaped(threadId))") { ... on PullRequestReviewThread { isResolved } }
        """)
        return (d["node"] as? [String: Any])?["isResolved"] as? Bool ?? false
    }

    func isReady(prId: String) async throws -> Bool {
        let d = try await check("""
        node(id: "\(escaped(prId))") { ... on PullRequest { isDraft } }
        """)
        return (d["node"] as? [String: Any])?["isDraft"] as? Bool == false
    }

    func pendingComment(prId: String, path: String, since: Date) async throws -> Bool {
        let d = try await check("""
        node(id: "\(escaped(prId))") { ... on PullRequest {
          reviews(last: 5, states: [PENDING]) { nodes { author { login } comments(last: 20) { nodes { path createdAt } } } }
        } }
        """)
        guard let me = Self.login(d) else { return false }
        let reviews = (((d["node"] as? [String: Any])?["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        return reviews.contains { r in
            ((r["author"] as? [String: Any])?["login"] as? String) == me
                && (((r["comments"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).contains {
                    $0["path"] as? String == path && (Self.date($0["createdAt"]).map { $0 >= since } ?? false)
                }
        }
    }

    func myReview(onPullRequest key: String, since: Date) async throws -> (at: Date, state: String?)? {
        let parts = key.split(separator: "#")
        let repo = parts.first.map { $0.split(separator: "/") } ?? []
        guard parts.count == 2, repo.count == 2, let number = Int(parts[1]) else { return nil }
        let d = try await check("""
        repository(owner: "\(escaped(String(repo[0])))", name: "\(escaped(String(repo[1])))") {
          pullRequest(number: \(number)) { reviews(last: 20) { nodes { author { login } submittedAt state } } }
        }
        """)
        guard let me = Self.login(d) else { return nil }
        let pr = ((d["repository"] as? [String: Any])?["pullRequest"] as? [String: Any])
        let reviews = ((pr?["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        return reviews
            .filter { (($0["author"] as? [String: Any])?["login"] as? String) == me }
            .compactMap { r in Self.date(r["submittedAt"]).map { (at: $0, state: r["state"] as? String) } }
            .filter { $0.at >= since.addingTimeInterval(-60) }
            .max { $0.at < $1.at }
    }

    func submittedReview(prId: String, since: Date) async throws -> Bool {
        let d = try await check("""
        node(id: "\(escaped(prId))") { ... on PullRequest {
          reviews(last: 5, states: [COMMENTED]) { nodes { author { login } submittedAt } }
        } }
        """)
        guard let me = Self.login(d) else { return false }
        let reviews = (((d["node"] as? [String: Any])?["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        return reviews.contains {
            ((($0["author"] as? [String: Any])?["login"] as? String) == me)
                && (Self.date($0["submittedAt"]).map { $0 >= since } ?? false)
        }
    }

    private func mutate(_ query: String, _ variables: [String: String]) async throws -> Data {
        let payload = try await post(query, variables: variables)
        if let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let errors = obj["errors"] as? [[String: Any]], !errors.isEmpty {
            throw ClientError.graphql(errors.compactMap { $0["message"] as? String })
        }
        return payload
    }
}
