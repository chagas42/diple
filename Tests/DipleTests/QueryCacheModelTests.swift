import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct QueryCacheModelTests {
    static func model(_ transport: StubTransport, preloading: Bool = false) -> AppModel {
        let model = AppModel(
            client: GitHubClient(transport: transport, tokens: CountingTokens(), metrics: Metrics(), retryDelays: []),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        model.preloadsTabs = preloading
        return model
    }

    @Test func aFailedFullRefreshSyncsOnceAndCountsOneFailure() async {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github.transport)
        await model.refresh()
        let before = github.transport.queries.count
        github.transport.respond { _ in .init(status: 502) }
        await model.refresh(full: true)
        #expect(model.failures == 1)
        let sent = FakeGitHub.syncKinds(github.transport.queries.dropFirst(before))
        #expect(sent == ["full", "full", "full"], "\(sent)")
    }

    @Test func watchingARepositoryMidSyncWaitsForThatSync() async throws {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github.transport)
        await model.refresh()
        let started = Locked<[(String, ContinuousClock.Instant)]>([])
        github.transport.respond { [github] q in
            let kind = FakeGitHub.kind(q)
            if kind != "other" { started.value.append((kind, .now)) }
            var reply = github.reply(q)
            reply.delay = .milliseconds(120)
            return reply
        }
        let steady = Task { await model.refresh() }
        try await Task.sleep(for: .milliseconds(30))
        model.toggleWatch("acme/repo0")
        await steady.value
        await model.tabsSettled()
        let beats = started.value.filter { $0.0 == "beat" }.map(\.1)
        let fulls = started.value.filter { $0.0 == "full" }.map(\.1)
        let lastBeat = try #require(beats.max())
        let firstFull = try #require(fulls.min())
        #expect(firstFull - lastBeat >= .milliseconds(100))
        #expect(model.watching == ["acme/repo0"])
        #expect(model.errorMessage == nil)
    }

    @Test func aReviewSurvivesAComment() async throws {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github.transport)
        await model.refresh()
        let pr = try #require(model.queue.mine.first)
        let review = AppModel.AIReview(result: ReviewResult(summary: "ok"), context: ReviewContext())
        model.queries.put(.aiReview(pr: pr.key, revision: pr.revision), review, forgetAfter: .seconds(3600))

        github.edit { w in w.update(pr.id) { $0.updatedAt = $0.updatedAt.addingTimeInterval(60) } }
        await model.refresh(full: true)
        let commented = try #require(model.queue.mine.first { $0.key == pr.key })
        #expect(commented.updatedAt != pr.updatedAt)
        #expect(model.aiReview(commented)?.result.summary == "ok")

        github.edit { w in w.update(pr.id) { $0.head = "new-commit" } }
        await model.refresh(full: true)
        let pushed = try #require(model.queue.mine.first { $0.key == pr.key })
        #expect(model.aiReview(pushed) == nil)
    }

    @Test func aBackgroundPreloadShowsNoSpinner() async throws {
        let gh = TabsGitHub()
        gh.delay(ranking: .milliseconds(200))
        let model = TabLoadingTests.model(gh, preloading: true)
        await model.refresh()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.refreshingTab == nil)
        await model.tabsSettled()
        #expect(!model.ranking.isEmpty)
    }

    @Test func aSyncAlreadyRunningDoesNotUndoAReread() async throws {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github.transport)
        await model.refresh()
        let pr = try #require(model.queue.mine.first)
        github.transport.respond { [github] q in
            if q.contains("pullRequest(number:") {
                let w = github.world
                let fresh = try! #require(w.all.first { $0.id == pr.id })
                let body: [String: Any] = ["data": ["viewer": ["login": w.viewer], "repository": ["pullRequest": FakeWorld.json(fresh)]]]
                return .init(body: try! JSONSerialization.data(withJSONObject: body))
            }
            var reply = github.reply(q)
            if q.contains("query Beat") { reply.delay = .milliseconds(300) }
            return reply
        }
        let steady = Task { await model.refresh() }
        try await Task.sleep(for: .milliseconds(50))
        github.edit { w in w.update(pr.id) { $0.title = "replied"; $0.updatedAt = $0.updatedAt.addingTimeInterval(60) } }
        await model.reread(pr)
        #expect(model.queue.mine.first { $0.key == pr.key }?.title == "replied")
        await steady.value
        await model.tabsSettled()
        #expect(model.queue.mine.first { $0.key == pr.key }?.title == "replied")
    }
}
