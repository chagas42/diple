import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct SyncProblemTests {
    static func model(_ github: FakeGitHub) -> AppModel {
        AppModel(
            client: GitHubClient(transport: github.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
    }

    @Test func aFailedSyncKeepsTheQueueItAlreadyHad() async {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github)
        await model.refresh()
        let before = model.queue.all.count
        #expect(before > 0)

        github.transport.respond { _ in .init(status: 502) }
        await model.refresh()
        #expect(model.syncProblem != nil)
        #expect(model.queue.all.count == before)
    }

    @Test func offlineSaysSoAndWhenTheQueueIsFrom() async {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github)
        model.isOnline = false
        #expect(model.syncProblem == "Offline")

        model.isOnline = true
        await model.refresh()
        #expect(model.syncProblem == nil)
        model.isOnline = false
        #expect(model.syncProblem?.hasPrefix("Offline · showing the queue from ") == true)
    }

    @Test func offlineWinsOverTheErrorThatLedToIt() async {
        let github = FakeGitHub(.realistic())
        let model = Self.model(github)
        github.transport.respond { _ in .init(failure: .notConnectedToInternet) }
        await model.refresh()
        #expect(model.errorMessage != nil)
        model.isOnline = false
        #expect(model.syncProblem == "Offline")
    }
}
