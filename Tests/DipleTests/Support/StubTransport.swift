import Foundation
@testable import Diple

final class StubTransport: Transport, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var body = Data()
        var delay: Duration = .zero
        var failure: URLError.Code?
    }

    private let lock = NSLock()
    private var handler: @Sendable (String) -> Reply
    private var recorded: [String] = []
    private var rawBodies: [Data] = []
    private var sentOnMain = 0
    private var inFlight = 0
    private var peak = 0

    init(_ handler: @escaping @Sendable (String) -> Reply) {
        self.handler = handler
    }

    convenience init(body: Data) {
        self.init { _ in Reply(body: body) }
    }

    var queries: [String] { lock.withLock { recorded } }
    var bodies: [Data] { lock.withLock { rawBodies } }
    var requestsOnMainThread: Int { lock.withLock { sentOnMain } }
    var peakConcurrency: Int { lock.withLock { peak } }

    func resetPeak() { lock.withLock { peak = 0 } }

    func respond(_ handler: @escaping @Sendable (String) -> Reply) {
        lock.withLock { self.handler = handler }
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let query = Self.query(of: request)
        let onMain = pthread_main_np() != 0
        let reply = lock.withLock {
            recorded.append(query)
            rawBodies.append(request.httpBody ?? Data())
            if onMain { sentOnMain += 1 }
            inFlight += 1
            peak = max(peak, inFlight)
            return handler(query)
        }
        defer { lock.withLock { inFlight -= 1 } }
        if reply.delay > .zero { try await Task.sleep(for: reply.delay) }
        if let code = reply.failure { throw URLError(code) }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        return (reply.body, response)
    }

    private static func query(of request: URLRequest) -> String {
        guard let body = request.httpBody,
              let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return "" }
        return (obj["query"] as? String) ?? ""
    }
}

final class CountingTokens: TokenSource, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var count: Int { lock.withLock { calls } }

    func current() async throws -> String {
        lock.withLock { calls += 1 }
        return "test-token"
    }
}
