import Foundation
import Testing
@testable import Diple

@Suite struct TokenBudgetTests {
    final class Sequence: @unchecked Sendable {
        private let lock = NSLock()
        private var statuses: [Int]
        init(_ statuses: [Int]) { self.statuses = statuses }
        func next() -> Int { lock.withLock { statuses.count > 1 ? statuses.removeFirst() : statuses[0] } }
    }

    static let ok = try! JSONSerialization.data(withJSONObject: ["data": [:]])

    @Test func tenRequestsSpawnGhOnce() async throws {
        let spawns = CountingTokens()
        let client = GitHubClient(
            transport: StubTransport(body: Self.ok), tokens: CachedTokenSource(spawns), metrics: Metrics()
        )
        for _ in 0..<10 { _ = try await client.raw("{ viewer { login } }") }
        #expect(spawns.count == 1)
    }

    @Test func concurrentRequestsShareOneSpawn() async throws {
        let spawns = CountingTokens()
        let client = GitHubClient(
            transport: StubTransport(body: Self.ok), tokens: CachedTokenSource(spawns), metrics: Metrics()
        )
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<10 { group.addTask { _ = try await client.raw("{ viewer { login } }") } }
            try await group.waitForAll()
        }
        #expect(spawns.count == 1)
    }

    @Test func anExpiredTokenIsFetchedAgainOnce() async throws {
        let spawns = CountingTokens()
        let statuses = Sequence([401, 200])
        let stub = StubTransport { _ in .init(status: statuses.next(), body: Self.ok) }
        let client = GitHubClient(transport: stub, tokens: CachedTokenSource(spawns), metrics: Metrics())
        _ = try await client.raw("{ viewer { login } }")
        #expect(spawns.count == 2)
        #expect(stub.queries.count == 2)
    }

    @Test func aTokenThatStaysRejectedFailsWithoutLooping() async {
        let spawns = CountingTokens()
        let stub = StubTransport { _ in .init(status: 401) }
        let client = GitHubClient(transport: stub, tokens: CachedTokenSource(spawns), metrics: Metrics())
        await #expect(throws: ClientError.self) { _ = try await client.raw("{ viewer { login } }") }
        #expect(stub.queries.count == 2)
        #expect(spawns.count == 2)
    }

    @Test func otherErrorsAreNotRetried() async {
        let stub = StubTransport { _ in .init(status: 502) }
        let client = GitHubClient(transport: stub, tokens: CachedTokenSource(CountingTokens()), metrics: Metrics())
        await #expect(throws: ClientError.self) { _ = try await client.raw("{ viewer { login } }") }
        #expect(stub.queries.count == 1)
    }
}
