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
        let added: Added = try await send(query)
        if let e = added.errors, !e.isEmpty { throw ClientError.graphql(e.map(\.message)) }

        try await submitPendingReview(prId: prId)
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

    func resolve(threadId: String) async throws {
        _ = try await mutate(
            """
            mutation($t: ID!) {
              resolveReviewThread(input: { threadId: $t }) { thread { id } }
            }
            """,
            ["t": threadId]
        )
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
