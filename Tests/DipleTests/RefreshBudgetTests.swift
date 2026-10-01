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
        await model.prefetchSettled()
        await model.tabsSettled()
        await model.settleState()
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

    static func model(_ github: FakeGitHub) -> AppModel {
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        model.preloadsTabs = false
        return model
    }

    @Test func aFullRefreshAskedForMidSyncStillRuns() async throws {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github)
        await model.refresh()
        let before = github.transport.queries.count
        github.transport.respond { [github] q in
            var reply = github.reply(q)
            reply.delay = .milliseconds(150)
            return reply
        }
        async let steady: Void = model.refresh()
        try await Task.sleep(for: .milliseconds(30))
        await model.refresh(full: true)
        await steady
        let kinds = FakeGitHub.syncKinds(github.transport.queries.dropFirst(before))
        #expect(kinds == ["beat", "beat", "beat", "full", "full", "full"])
    }

    @Test func twoRefreshesAtOnceShareOneSync() async throws {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github)
        await model.refresh()
        let before = github.transport.queries.count
        async let a: Void = model.refresh()
        async let b: Void = model.refresh()
        _ = await (a, b)
        #expect(FakeGitHub.syncKinds(github.transport.queries.dropFirst(before)) == ["beat", "beat", "beat"])
    }

    @Test func watchingARepositoryFetchesItsPullRequestsAtOnce() async throws {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github)
        await model.refresh()
        let before = github.transport.queries.count
        model.toggleWatch("acme/repo0")
        await model.tabsSettled()
        let sent = github.transport.queries.dropFirst(before)
        #expect(FakeGitHub.syncKinds(sent).allSatisfy { $0 == "full" })
        #expect(sent.contains { $0.contains("repo:acme/repo0") })
    }

    @Test func wakingUpForcesAFullFetch() async throws {
        let github = FakeGitHub(.realistic())
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        await model.refresh()
        await model.refresh(full: true)
        #expect(FakeGitHub.syncKinds(github.transport.queries) == Array(repeating: "full", count: 6))
    }
}
