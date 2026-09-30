import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct LaunchCacheTests {
    static func model(_ dir: URL, _ transport: StubTransport) -> AppModel {
        AppModel(
            client: GitHubClient(transport: transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: dir, metrics: Metrics())
        )
    }

    @Test func theLastQueueIsOnScreenBeforeAnyRequest() async {
        let dir = StoreDiffTests.tempDirectory()
        let first = Self.model(dir, StubTransport(body: FakeWorld.realistic().queueResponse()))
        await first.refresh()
        #expect(first.queue.all.count == 36)
        await first.settleState()

        let silent = StubTransport(body: Data())
        let relaunched = Self.model(dir, silent)
        relaunched.restoreCached()
        #expect(relaunched.queue.all.count == 36)
        #expect(relaunched.queue.all == first.queue.all)
        #expect(silent.queries.isEmpty)
    }

    @Test func aFreshInstallStartsEmpty() {
        let model = Self.model(StoreDiffTests.tempDirectory(), StubTransport(body: Data()))
        model.restoreCached()
        #expect(model.queue.all.isEmpty)
    }

    @Test func aRefreshReplacesTheCachedQueue() async {
        let dir = StoreDiffTests.tempDirectory()
        let github = FakeGitHub(.realistic())
        let first = Self.model(dir, github.transport)
        await first.refresh()
        await first.settleState()

        github.edit { $0.following.removeLast(8) }
        let second = Self.model(dir, github.transport)
        second.restoreCached()
        await second.refresh()
        #expect(second.errorMessage == nil)
        #expect(second.queue.following.count == 10)
        await second.settleState()

        let third = Self.model(dir, StubTransport(body: Data()))
        third.restoreCached()
        #expect(third.queue.following.count == 10)
    }
}

@MainActor
@Suite struct LenientCacheTests {
    @Test func anUnreadableCachedQueueNeverCostsTheRestOfTheState() throws {
        var state = StoredState()
        state.following = ["marina"]
        state.settings.interval = 90
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        var cache = json["cache"] as! [String: Any]
        cache["lastQueue"] = ["viewer": 42, "mine": "not a list"]
        json["cache"] = cache
        let bytes = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(StoredState.self, from: bytes)
        #expect(decoded.cache.queue == nil)
        #expect(decoded.following == ["marina"])
        #expect(decoded.settings.interval == 90)
    }
}
