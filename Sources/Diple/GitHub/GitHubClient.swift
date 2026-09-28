import Foundation

enum ClientError: LocalizedError {
    case http(Int)
    case graphql([String])
    case empty

    var errorDescription: String? {
        switch self {
        case .http(let c):      "GitHub respondeu HTTP \(c)"
        case .graphql(let m):   m.joined(separator: " · ")
        case .empty:            "GitHub answered with no data"
        }
    }
}

struct GitHubClient: Sendable {
    private let endpoint = URL(string: "https://api.github.com/graphql")!

    func send<T: Decodable & Sendable>(_ query: String) async throws -> T {
        let token = try await Task.detached(priority: .utility) {
            try Token.current()
        }.value

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Diple/0.1", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(["query": query])
        req.timeoutInterval = 20

        let (payload, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(T.self, from: payload)
    }

    func fetchQueue() async throws -> Queue {
        let token = try await Task.detached(priority: .utility) {
            try Token.current()
        }.value

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Diple/0.1", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(["query": Query.queue])
        req.timeoutInterval = 20

        let (date, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let body = try dec.decode(RawResponse.self, from: date)

        if let erros = body.errors, !erros.isEmpty {
            throw ClientError.graphql(erros.map(\.message))
        }
        guard let d = body.data else { throw ClientError.empty }

        let viewer = d.viewer.login
        return Queue(
            viewer: viewer,
            mine: d.mine.nodes.compactMap { PR($0, meuLogin: viewer) },
            toReview: d.toReview.nodes.compactMap { PR($0, meuLogin: viewer) },
            following: d.following.nodes.compactMap { PR($0, meuLogin: viewer) },
            rateLimitLeft: d.rateLimit?.remaining ?? 0
        )
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
        let token = try await Task.detached(priority: .utility) { try Token.current() }.value

        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        req.httpMethod = "POST"
        req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Diple/0.1", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables]
        )
        req.timeoutInterval = 20

        let (date, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }

        if let obj = try? JSONSerialization.jsonObject(with: date) as? [String: Any],
           let erros = obj["errors"] as? [[String: Any]], !erros.isEmpty {
            throw ClientError.graphql(erros.compactMap { $0["message"] as? String })
        }
        return date
    }
}
