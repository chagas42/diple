import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct StoreDiffTests {
    static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("diple-tests-\(UUID().uuidString)", isDirectory: true)
    }

    static func queue(_ world: FakeWorld) async throws -> Queue {
        let client = GitHubClient(transport: StubTransport(body: world.queueResponse()), tokens: CountingTokens(), metrics: Metrics())
        return try await client.fetchQueue()
    }

    @Test func firstRunIsSilent() async throws {
        let store = Store(directory: Self.tempDirectory(), metrics: Metrics())
        let events = store.diff(try await Self.queue(.realistic()), meuLogin: "you")
        #expect(events.isEmpty)
        #expect(store.state.hasRunBefore)
    }

    @Test func unchangedQueueRaisesNothing() async throws {
        let store = Store(directory: Self.tempDirectory(), metrics: Metrics())
        let q = try await Self.queue(.realistic())
        _ = store.diff(q, meuLogin: "you")
        #expect(store.diff(q, meuLogin: "you").isEmpty)
    }

    @Test func eachChangeRaisesItsEvent() async throws {
        let store = Store(directory: Self.tempDirectory(), metrics: Metrics())
        var world = FakeWorld.realistic()
        _ = store.diff(try await Self.queue(world), meuLogin: "you")

        let later = FakeWorld.epoch.addingTimeInterval(120)
        world.toReview.append(FakeWorld.pr(40, author: "newcomer", viewer: "you"))
        world.toReview[world.toReview.count - 1].updatedAt = later
        world.update("PR_0") { $0.checks = "FAILURE" }
        world.update("PR_1") {
            $0.threads[0].comments.append(FakeComment(author: "reviewer9", at: later, body: "@you what about the retry?"))
        }
        world.update("PR_2") { $0.decision = "APPROVED" }
        world.update("PR_20") {
            $0.conversation.append(FakeComment(author: "reviewer8", at: later, body: "looks fine"))
        }

        let events = store.diff(try await Self.queue(world), meuLogin: "you")
        let byKind = Dictionary(grouping: events, by: \.kind).mapValues { $0.map(\.key).sorted() }

        #expect(byKind[.reviewRequested] == ["acme/repo0#140"])
        #expect(byKind[.checkFailed] == ["acme/repo0#100"])
        #expect(byKind[.repliedToYou] == ["acme/repo1#101"])
        #expect(byKind[.approved] == ["acme/repo2#102"])
        #expect(byKind[.commented] == ["acme/repo0#120"])
        #expect(events.count == 5)
        #expect(store.state.unread == Set(events.map(\.key)))
    }

    @Test func stateSurvivesAReload() async throws {
        let dir = Self.tempDirectory()
        let store = Store(directory: dir, metrics: Metrics())
        _ = store.diff(try await Self.queue(.realistic()), meuLogin: "you")
        await store.settle()
        let reloaded = Store(directory: dir, metrics: Metrics())
        #expect(reloaded.state.hasRunBefore)
        #expect(reloaded.state.prs.count == 36)
    }
}
