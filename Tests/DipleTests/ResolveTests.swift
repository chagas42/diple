import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct ResolveTests {
    @Test func resolvingAThreadRereadsOnlyThatPullRequest() async throws {
        let github = FakeGitHub(.realistic())
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        model.preloadsTabs = false
        await model.refresh()
        let pr = try #require(model.queue.mine.first)
        model.selected = pr
        github.transport.respond { [github] q in
            if q.contains("resolveReviewThread") {
                let body: [String: Any] = ["data": ["resolveReviewThread": ["thread": ["id": "t1"]]]]
                return .init(body: try! JSONSerialization.data(withJSONObject: body))
            }
            if q.contains("pullRequest(number:") {
                let w = github.world
                let fresh = try! #require(w.all.first { $0.id == pr.id })
                let body: [String: Any] = ["data": ["viewer": ["login": w.viewer], "repository": ["pullRequest": FakeWorld.json(fresh)]]]
                return .init(body: try! JSONSerialization.data(withJSONObject: body))
            }
            return github.reply(q)
        }
        let before = github.transport.queries.count
        let failure = await model.resolve(thread: "t1")
        #expect(failure == nil)
        let sent = github.transport.queries.dropFirst(before)
        #expect(sent.contains { $0.contains("pullRequest(number:") })
        #expect(FakeGitHub.syncKinds(sent).isEmpty)
    }
}
