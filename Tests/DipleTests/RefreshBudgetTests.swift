import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct RefreshBudgetTests {
    static let budgetBytes = 8_000

    @Test func aSteadyRefreshCostsOneSmallRequestAndNoWrite() async throws {
        let github = FakeGitHub(.realistic())
        let metrics = Metrics()
        let tokens = CountingTokens()
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CachedTokenSource(tokens), metrics: metrics),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: metrics)
        )
        await model.refresh()
        await model.settleState()
        await model.prefetchSettled()
        metrics.reset()

        for _ in 0..<5 {
            await model.refresh()
            await model.settleState()
        }
        let s = metrics.snapshot()
        #expect(model.errorMessage == nil)
        #expect(s.count(.requests) == 15)
        #expect(s.count(.bytesIn) < 5 * Self.budgetBytes)
        #expect(s.count(.storeWrites) == 0)
        #expect(s.count(.storeWritesOnMain) == 0)
        #expect(tokens.count == 1)
        #expect(FakeGitHub.syncKinds(github.transport.queries).suffix(15).allSatisfy { $0 == "beat" })
    }

    @Test func aRelaunchStartsWithAHeartbeatNotAFullFetch() async throws {
        let github = FakeGitHub(.realistic())
        let dir = StoreDiffTests.tempDirectory()
        func model() -> AppModel {
            AppModel(
                client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics()),
                store: Store(directory: dir, metrics: Metrics())
            )
        }
        let first = model()
        await first.refresh()
        await first.settleState()

        let relaunched = model()
        relaunched.restoreCached()
        let before = github.transport.queries.count
        await relaunched.refresh()
        #expect(FakeGitHub.syncKinds(github.transport.queries.dropFirst(before)) == ["beat", "beat", "beat"])
        #expect(relaunched.queue.all == first.queue.all)
    }

    @Test func wakingUpForcesAFullFetch() async throws {
        let github = FakeGitHub(.realistic())
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        await model.refresh()
        await model.refresh(full: true)
        #expect(FakeGitHub.syncKinds(github.transport.queries) == ["full", "full"])
    }
}
