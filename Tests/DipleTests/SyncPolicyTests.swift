import Foundation
import Testing
@testable import Diple

@Suite struct SyncPolicyTests {
    static let now = FakeWorld.epoch

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let policy: SyncPolicy
        let expected: TimeInterval?
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "visible uses the base interval",
             policy: SyncPolicy(base: 60, visible: true), expected: 60),
        Case(name: "hidden waits twice as long",
             policy: SyncPolicy(base: 60), expected: 120),
        Case(name: "low power doubles again",
             policy: SyncPolicy(base: 60, lowPower: true), expected: 240),
        Case(name: "offline does not poll",
             policy: SyncPolicy(base: 60, online: false, visible: true), expected: nil),
        Case(name: "one failure backs off",
             policy: SyncPolicy(base: 60, failures: 1, visible: true), expected: 120),
        Case(name: "three failures back off more",
             policy: SyncPolicy(base: 60, failures: 3, visible: true), expected: 480),
        Case(name: "backoff is capped at ten minutes",
             policy: SyncPolicy(base: 60, failures: 9, visible: true), expected: 600),
        Case(name: "an exhausted rate limit waits for the reset",
             policy: SyncPolicy(base: 60, visible: true, rateLimitLeft: 20,
                                rateLimitResetAt: now.addingTimeInterval(900)), expected: 905),
        Case(name: "a rate limit already reset is ignored",
             policy: SyncPolicy(base: 60, visible: true, rateLimitLeft: 20,
                                rateLimitResetAt: now.addingTimeInterval(-10)), expected: 60),
        Case(name: "a healthy rate limit is ignored",
             policy: SyncPolicy(base: 60, visible: true, rateLimitLeft: 4000,
                                rateLimitResetAt: now.addingTimeInterval(900)), expected: 60),
    ]

    @Test(arguments: cases)
    func nextDelay(_ c: Case) {
        #expect(c.policy.nextDelay(now: Self.now) == c.expected)
    }
}

@MainActor
@Suite struct PollingTests {
    static func model(_ github: FakeGitHub) -> AppModel {
        AppModel(
            client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics(), retryDelays: [.zero, .zero]),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
    }

    @Test func offlineMakesNoRequest() async {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github)
        model.isOnline = false
        await model.refresh()
        #expect(github.transport.queries.isEmpty)
    }

    @Test func failuresCountUpAndASuccessResetsThem() async {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github)
        github.transport.respond { _ in .init(status: 502) }
        await model.refresh()
        await model.refresh()
        #expect(model.failures == 2)
        #expect(model.policy.failures == 2)
        let fresh = FakeGitHub(.realistic())
        github.transport.respond { [fresh] q in
            q.contains("query Beat") ? .init(body: fresh.world.heartbeatResponse(for: q)) : .init(body: fresh.world.queueResponse())
        }
        await model.refresh()
        #expect(model.failures == 0)
        #expect(model.errorMessage == nil)
    }

    @Test func aWakeWhileOfflineBecomesAFullFetchWhenTheNetworkReturns() async {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github)
        await model.refresh()
        model.isOnline = false
        await model.refresh(full: true)
        model.isOnline = true
        let before = github.transport.queries.count
        await model.refresh()
        #expect(FakeGitHub.syncKinds(github.transport.queries.dropFirst(before)) == ["full", "full", "full"])
        await model.refresh()
        #expect((FakeGitHub.syncKinds(github.transport.queries).last ?? "") == "beat")
    }
}
