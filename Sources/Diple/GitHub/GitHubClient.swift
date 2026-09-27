import Foundation

enum ClientError: LocalizedError {
    case http(Int)
    case graphql([String])
    case empty

    var errorDescription: String? {
        switch self {
        case .http(let c):      "GitHub answered HTTP \(c)"
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

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let body = try dec.decode(RawResponse.self, from: data)

        if let errors = body.errors, !errors.isEmpty {
            throw ClientError.graphql(errors.map(\.message))
        }
        guard let d = body.data else { throw ClientError.empty }

        let viewer = d.viewer.login
        return Queue(
            viewer: viewer,
            mine: d.mine.nodes.compactMap { PR($0, viewerLogin: viewer) },
            toReview: d.toReview.nodes.compactMap { PR($0, viewerLogin: viewer) },
            following: d.following.nodes.compactMap { PR($0, viewerLogin: viewer) },
            rateLimitLeft: d.rateLimit?.remaining ?? 0
        )
    }
}

extension GitHubClient {
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

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }

        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = obj["errors"] as? [[String: Any]], !errors.isEmpty {
            throw ClientError.graphql(errors.compactMap { $0["message"] as? String })
        }
        return data
    }
}
