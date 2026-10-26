import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct ReadyForReviewTests {
    nonisolated static func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }

    nonisolated static let marked = StubTransport.Reply(body: json(["data": ["markPullRequestReadyForReview": ["pullRequest": ["id": "PR_0", "isDraft": false]]]]))

    nonisolated static func refused(_ message: String) -> StubTransport.Reply {
        .init(body: json(["data": ["markPullRequestReadyForReview": NSNull()], "errors": [["message": message]]]))
    }

    static func rig() async -> (FakeGitHub, AppModel) {
        var world = FakeWorld.realistic()
        world.update("PR_0") { $0.draft = true }
        let github = FakeGitHub(world)
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics(), retryDelays: [.zero, .zero]),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        model.preloadsTabs = false
        await model.refresh()
        return (github, model)
    }

    nonisolated static func answer(_ github: FakeGitHub, mutation: @escaping @Sendable () -> StubTransport.Reply) {
        github.transport.respond { [github] q in
            if q.contains("markPullRequestReadyForReview") {
                let reply = mutation()
                if reply.status == 200, !String(decoding: reply.body, as: UTF8.self).contains("errors") {
                    github.edit { $0.update("PR_0") { $0.draft = false } }
                }
                return reply
            }
            if q.contains("pullRequest(number:") {
                let w = github.world
                let fresh = w.all.first { $0.id == "PR_0" }!
                return .init(body: json(["data": ["viewer": ["login": w.viewer], "repository": ["pullRequest": FakeWorld.json(fresh)]]]))
            }
            if q.contains("MutationCheck") {
                let draft = github.world.all.first { $0.id == "PR_0" }!.draft
                return .init(body: json(["data": ["viewer": ["login": "you"], "node": ["isDraft": draft]]]))
            }
            return github.reply(q)
        }
    }

    func draft(_ model: AppModel) -> Bool? { model.queue.mine.first { $0.id == "PR_0" }?.draft }

    @Test func markingReadyFlipsAtOnceAndKeepsGitHubsAnswer() async throws {
        let (github, model) = await Self.rig()
        let slow = StubTransport.Reply(body: Self.marked.body, delay: .milliseconds(300))
        Self.answer(github) { slow }
        let pr = try #require(model.queue.mine.first { $0.id == "PR_0" })
        model.selected = pr

        let marking = Task { await model.markReady(pr) }
        while !github.transport.queries.contains(where: { $0.contains("markPullRequestReadyForReview") }) {
            await Task.yield()
        }
        #expect(draft(model) == false)
        #expect(model.markingReady == [pr.key])

        #expect(await marking.value == nil)
        #expect(draft(model) == false)
        #expect(model.selected?.draft == false)
        #expect(model.markingReady.isEmpty)
        #expect(github.transport.queries.contains { $0.contains("pullRequest(number:") })
        let sent = try #require(github.transport.bodies.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .first { ($0["query"] as? String)?.contains("markPullRequestReadyForReview") == true })
        #expect((sent["variables"] as? [String: String])?["p"] == "PR_0")
    }

    @Test func aRefusalPutsTheDraftBackAndSaysWhy() async throws {
        let (github, model) = await Self.rig()
        Self.answer(github) {
            Self.refused("Your token has not been granted the required scopes to execute this query. The 'markPullRequestReadyForReview' field requires one of the following scopes: ['repo'], but your token has only been granted the: ['read:org'] scopes.")
        }
        let pr = try #require(model.queue.mine.first { $0.id == "PR_0" })
        model.selected = pr

        let failure = await model.markReady(pr)
        #expect(failure == ReadyForReview.missingScope)
        #expect(draft(model) == true)
        #expect(model.selected?.draft == true)
        #expect(model.markingReady.isEmpty)
        #expect(!github.transport.queries.contains { $0.contains("pullRequest(number:") })
    }

    @Test func aMarkThatLandedDespiteA502IsASuccess() async throws {
        let (github, model) = await Self.rig()
        github.transport.respond { [github] q in
            if q.contains("markPullRequestReadyForReview") {
                github.edit { $0.update("PR_0") { $0.draft = false } }
                return .init(status: 502)
            }
            if q.contains("MutationCheck") {
                return .init(body: Self.json(["data": ["viewer": ["login": "you"], "node": ["isDraft": false]]]))
            }
            if q.contains("pullRequest(number:") {
                let w = github.world
                return .init(body: Self.json(["data": ["viewer": ["login": w.viewer], "repository": ["pullRequest": FakeWorld.json(w.all.first { $0.id == "PR_0" }!)]]]))
            }
            return github.reply(q)
        }
        let pr = try #require(model.queue.mine.first { $0.id == "PR_0" })
        #expect(await model.markReady(pr) == nil)
        #expect(draft(model) == false)
        #expect(github.transport.queries.filter { $0.contains("markPullRequestReadyForReview") }.count == 1)
    }

    @Test func onlyYourOwnDraftsCanBeMarked() async throws {
        let (github, model) = await Self.rig()
        Self.answer(github) { Self.marked }
        let ready = try #require(model.queue.mine.first { !$0.draft })
        let theirs = try #require(model.queue.following.first)
        #expect(!model.canMarkReady(ready))
        #expect(!model.canMarkReady(theirs))
        #expect(await model.markReady(ready) == nil)
        #expect(await model.markReady(theirs) == nil)
        #expect(!github.transport.queries.contains { $0.contains("markPullRequestReadyForReview") })
    }

    @Test func refusalsReadAsWhatToDo() {
        #expect(ReadyForReview.explain(ClientError.graphql(["Resource not accessible by integration"])) == ReadyForReview.fineGrained)
        #expect(ReadyForReview.explain(ClientError.graphql(["you does not have the correct permissions to execute `MarkPullRequestReadyForReview`"])) == ReadyForReview.refused)
        #expect(ReadyForReview.explain(ClientError.http(403)) == ReadyForReview.refused)
        #expect(ReadyForReview.explain(ClientError.graphql(["Pull request is closed"])) == "Pull request is closed")
    }
}
