import Foundation

protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionTransport: Transport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

protocol TokenSource: Sendable {
    func current() async throws -> String
    func invalidate() async
}

extension TokenSource {
    func invalidate() async {}
}

struct GHTokenSource: TokenSource {
    func current() async throws -> String {
        try await Task.detached(priority: .utility) {
            Metrics.shared.count(.tokenSpawns)
            return try Token.current()
        }.value
    }
}

actor CachedTokenSource: TokenSource {
    static let shared = CachedTokenSource(GHTokenSource())

    private let source: any TokenSource
    private var cached: String?
    private var pending: Task<String, Error>?

    init(_ source: any TokenSource) {
        self.source = source
    }

    func current() async throws -> String {
        if let cached { return cached }
        if let pending { return try await pending.value }
        let task = Task { [source] in try await source.current() }
        pending = task
        defer { pending = nil }
        let token = try await task.value
        cached = token
        return token
    }

    func invalidate() async {
        cached = nil
    }
}
