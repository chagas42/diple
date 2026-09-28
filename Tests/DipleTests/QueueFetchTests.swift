import Foundation
import Testing
@testable import Diple

@Suite struct QueueFetchTests {
    @Test func realisticFixtureIsAsHeavyAsTheRealQueue() {
        let bytes = FakeWorld.realistic().queueResponse().count
        #expect(bytes > 350_000)
        #expect(bytes < 550_000)
    }

    @Test func decodesEverySearch() async throws {
        let world = FakeWorld.realistic()
        let client = GitHubClient(transport: StubTransport(body: world.queueResponse()), tokens: CountingTokens(), metrics: Metrics())
        let queue = try await client.fetchQueue()
        #expect(queue.viewer == "you")
        #expect(queue.mine.count == 14)
        #expect(queue.toReview.count == 4)
        #expect(queue.following.count == 18)
        #expect(queue.mine.allSatisfy { $0.isMine })
        #expect(queue.all.allSatisfy { $0.checks == .passing })
    }

    @Test func lastCommentSkipsBotsAndTheViewer() async throws {
        let world = FakeWorld.realistic()
        let client = GitHubClient(transport: StubTransport(body: world.queueResponse()), tokens: CountingTokens(), metrics: Metrics())
        let queue = try await client.fetchQueue()
        for (i, pr) in queue.all.enumerated() {
            #expect(pr.lastComment?.author == "reviewer\(i % 5)")
            #expect(pr.lastComment?.location == nil)
        }
    }

    @Test func threadsKeepTheirDiffHunk() async throws {
        let world = FakeWorld.realistic()
        let client = GitHubClient(transport: StubTransport(body: world.queueResponse()), tokens: CountingTokens(), metrics: Metrics())
        let pr = try await client.fetchQueue().following[0]
        #expect(pr.threads.count == 3)
        #expect(pr.threads.allSatisfy { $0.diffHunk?.hasPrefix("@@") == true })
    }

    @Test func httpErrorsSurface() async {
        let stub = StubTransport { _ in .init(status: 502) }
        let client = GitHubClient(transport: stub, tokens: CountingTokens(), metrics: Metrics(), retryDelays: [.zero, .zero])
        await #expect(throws: ClientError.self) { try await client.fetchQueue() }
    }

    @Test func aFullFetchIsOneRequestPerSectionAndMetricsSeeThem() async throws {
        let world = FakeWorld.realistic()
        let body = world.queueResponse()
        let metrics = Metrics()
        let client = GitHubClient(transport: StubTransport(body: body), tokens: CountingTokens(), metrics: metrics)
        _ = try await client.fetchQueue()
        let s = metrics.snapshot()
        #expect(s.count(.requests) == 3)
        #expect(s.count(.bytesIn) == 3 * body.count)
        #expect(s.millis(.request).count == 3)
    }
}
