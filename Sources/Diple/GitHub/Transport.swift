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
}

struct GHTokenSource: TokenSource {
    func current() async throws -> String {
        try await Task.detached(priority: .utility) {
            Metrics.shared.count(.tokenSpawns)
            return try Token.current()
        }.value
    }
}
