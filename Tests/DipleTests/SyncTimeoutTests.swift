import Foundation
import Testing
@testable import Diple

@Suite struct SyncTimeoutTests {
    static let later = FakeWorld.epoch.addingTimeInterval(600)

    static func engine(_ github: FakeGitHub, clock: FakeClock = FakeClock()) -> SyncEngine {
        SyncEngine(
            client: GitHubClient(
                transport: github.transport, tokens: CountingTokens(), metrics: Metrics(), retryDelays: [.zero, .zero]
            ),
            now: { clock.now }
        )
    }

    @Test func aSectionThatTimesOutKeepsWhatItHadAndTheOthersUpdate() async throws {
        let github = FakeGitHub(.realistic())
        let engine = Self.engine(github)
        let first = try await engine.sync(full: true)
        let oldFollowing = first.queue.following

        github.edit { w in
            w.update("PR_0") { $0.title = "Mine, renamed"; $0.updatedAt = Self.later }
            w.update("PR_20") { $0.title = "Following, renamed"; $0.updatedAt = Self.later }
        }
        github.timeOut(["following"])
        let partial = try await engine.sync(full: true)

        #expect(partial.staleSections == [.following])
        #expect(partial.queue.mine.first { $0.id == "PR_0" }?.title == "Mine, renamed")
        #expect(partial.queue.following == oldFollowing)
        #expect(partial.staleMessage == "Following could not sync — showing what it had")
        if case ClientError.http(504, 3)? = partial.error {} else { Issue.record("expected a 504 after 3 tries, got \(String(describing: partial.error))") }
    }

    @Test func afterAPartialFullTheNextSyncIsFullAgain() async throws {
        let github = FakeGitHub(.realistic())
        let engine = Self.engine(github)
        _ = try await engine.sync(full: true)
        github.timeOut(["following"])
        _ = try await engine.sync(full: true)

        github.timeOut([])
        let before = github.transport.queries.count
        let next = try await engine.sync()
        #expect(next.staleSections.isEmpty)
        #expect(Set(FakeGitHub.syncKinds(github.transport.queries.dropFirst(before))) == ["full"])
    }

    @Test func whenEverySectionTimesOutTheSyncFails() async {
        let github = FakeGitHub(.realistic())
        let engine = Self.engine(github)
        github.timeOut(["mine", "toReview", "following"])
        await #expect(throws: ClientError.self) { _ = try await engine.sync(full: true) }
    }

    @Test func aFirstLoadWithOneSectionDownShowsTheRest() async throws {
        let github = FakeGitHub(.realistic())
        let engine = Self.engine(github)
        github.timeOut(["toReview"])
        let outcome = try await engine.sync()
        #expect(outcome.queue.mine.count == 14)
        #expect(outcome.queue.following.count == 18)
        #expect(outcome.queue.toReview.isEmpty)
        #expect(outcome.staleSections == [.toReview])
    }

    @Test func detailsGoInBatchesOfTenTwoAtATime() async throws {
        let world = FakeWorld.realistic()
        let stub = StubTransport { q in
            .init(body: world.detailResponse(FakeGitHub.ids(in: q)), delay: .milliseconds(40))
        }
        let client = GitHubClient(transport: stub, tokens: CountingTokens(), metrics: Metrics())
        let ids = world.all.prefix(25).map(\.id)
        let fetch = await client.fetchPRs(ids: ids)
        #expect(fetch.prs.count == 25)
        #expect(fetch.failed.isEmpty)
        #expect(stub.queries.map { FakeGitHub.ids(in: $0).count }.sorted() == [5, 10, 10])
        #expect(stub.peakConcurrency == 2)
    }

    @Test func aBatchThatTimesOutKeepsTheOldVersionAndComesBackNextBeat() async throws {
        let github = FakeGitHub(.realistic())
        let engine = Self.engine(github)
        _ = try await engine.sync(full: true)
        github.edit { w in w.update("PR_3") { $0.title = "Renamed"; $0.updatedAt = Self.later } }
        github.timeOut(["PR_3"])

        let stale = try await engine.sync()
        #expect(stale.stalePRs == 1)
        #expect(stale.queue.mine.first { $0.id == "PR_3" }?.title != "Renamed")
        #expect(stale.staleMessage == "1 pull request could not update — showing what it had")

        github.timeOut([])
        let healed = try await engine.sync()
        #expect(healed.stalePRs == 0)
        #expect(healed.queue.mine.first { $0.id == "PR_3" }?.title == "Renamed")
    }

    @Test func aNewPullRequestInABatchThatTimesOutWaitsForTheNextBeat() async throws {
        let github = FakeGitHub(.realistic())
        let engine = Self.engine(github)
        _ = try await engine.sync(full: true)
        github.edit { w in w.toReview.append(FakeWorld.pr(77, author: "newcomer", viewer: "you")) }
        github.timeOut(["PR_77"])

        let stale = try await engine.sync()
        #expect(!stale.queue.toReview.contains { $0.id == "PR_77" })
        #expect(stale.stalePRs == 1)

        github.timeOut([])
        let healed = try await engine.sync()
        #expect(healed.queue.toReview.contains { $0.id == "PR_77" })
    }

    @Test func aRetryIsCountedWhetherItRecoversOrNot() async throws {
        let posthog = StubTransport { _ in .init(status: 200) }
        let telemetry = TelemetryTests.make(posthog)
        let calls = TokenBudgetTests.Counter()
        let flaky = StubTransport { _ in calls.next() == 1 ? .init(status: 504) : .init(body: Data("{\"data\":{}}".utf8)) }
        let client = GitHubClient(
            transport: flaky, tokens: CountingTokens(), metrics: Metrics(),
            telemetry: telemetry, retryDelays: [.zero, .zero]
        )
        _ = try await client.raw("{ viewer { login } }")

        let dead = GitHubClient(
            transport: StubTransport { _ in .init(status: 502) }, tokens: CountingTokens(), metrics: Metrics(),
            telemetry: telemetry, retryDelays: [.zero, .zero]
        )
        _ = try? await dead.raw("{ viewer { login } }")

        await telemetry.flush()
        let events = TelemetryTests.events(in: try #require(posthog.bodies.first))
        let props = events.filter { $0["event"] as? String == "github_retry" }.map { $0["properties"] as! [String: Any] }
        #expect(props.count == 2)
        #expect(props[0]["outcome"] as? String == "recovered")
        #expect(props[0]["status"] as? Int == 504)
        #expect(props[0]["attempts"] as? Int == 2)
        #expect(props[1]["outcome"] as? String == "failed")
        #expect(props[1]["attempts"] as? Int == 3)
        #expect(props[1]["request"] as? String == "other")
    }
}

@MainActor
@Suite struct PartialSyncOnScreenTests {
    @Test func aSectionThatTimesOutIsNamedAndTheQueueStays() async {
        let github = FakeGitHub(.realistic())
        let model = AppModel(
            client: GitHubClient(
                transport: github.transport, tokens: CountingTokens(), metrics: Metrics(), retryDelays: [.zero, .zero]
            ),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        github.timeOut(["following"])
        await model.refresh()
        #expect(model.queue.mine.count == 14)
        #expect(model.syncProblem == "Following could not sync — showing what it had")
        #expect(model.failures == 0)
        #expect(model.partialFailures == 1)
        #expect(model.policy.nextDelay() == SyncPolicy.partialRetry)

        github.timeOut([])
        await model.refresh()
        #expect(model.syncProblem == nil)
        #expect(model.queue.following.count == 18)
        #expect(model.failures == 0)
        #expect(model.partialFailures == 0)
    }
}
