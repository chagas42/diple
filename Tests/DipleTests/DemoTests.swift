import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct DemoTests {
    @Test func theDemoRunsTheRealPathWithoutARequest() async {
        let silent = StubTransport(body: Data())
        let model = AppModel(
            client: GitHubClient(transport: silent, tokens: CountingTokens(), metrics: Metrics()),
            store: Demo.store(),
            answer: Demo.answer
        )
        model.restoreCached()
        model.settings.rankingMode = .team
        await model.refresh()
        model.loadTab(.ranking)
        await model.tabsSettled()

        #expect(model.queue.all == Demo.queue.all)
        #expect(model.unread == Demo.unread)
        #expect(model.team == Demo.team)
        #expect(!model.ranking.isEmpty)
        #expect(model.activity.count == Demo.activity.count)
        #expect(model.watching == Demo.watching)
        #expect(silent.queries.isEmpty)
    }

    @Test func aDemoSyncFindsNothingNewToNotify() async {
        let model = AppModel(
            client: GitHubClient(transport: StubTransport(body: Data()), tokens: CountingTokens(), metrics: Metrics()),
            store: Demo.store(),
            answer: Demo.answer
        )
        model.restoreCached()
        await model.refresh()
        await model.refresh()
        #expect(model.unread == Demo.unread)
    }
}
