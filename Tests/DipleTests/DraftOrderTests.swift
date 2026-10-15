import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct DraftOrderTests {
    @Test func yourDraftsComeAfterYourReadyPullRequests() async throws {
        var world = FakeWorld.realistic()
        world.update("PR_0") { $0.draft = true }
        world.update("PR_3") { $0.draft = true }
        let github = FakeGitHub(world)
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        model.preloadsTabs = false
        await model.refresh()

        let shown = model.prs(.mine).map(\.number)
        let ready = model.queue.mine.filter { !$0.draft }.map(\.number)
        #expect(shown == ready + [100, 103])
        #expect(model.count(.mine) == model.queue.mine.count)
        #expect(model.rest.suffix(2).map(\.number) == [100, 103])
    }
}
