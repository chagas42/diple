import Foundation
import Testing
@testable import Diple

@Suite struct ChangeFeedTests {
    static func thread(
        _ repo: String = "acme/api", reason: String = "review_requested",
        type: String = "PullRequest", updated: String = "2026-10-02T18:00:00Z"
    ) -> [String: Any] {
        [
            "reason": reason,
            "updated_at": updated,
            "subject": ["type": type, "title": "Something"],
            "repository": ["full_name": repo],
        ]
    }

    static func ok(_ threads: [[String: Any]], lastModified: String = "Fri, 02 Oct 2026 18:00:00 GMT") -> ChangeFeed.Reply {
        ChangeFeed.Reply(
            status: 200, lastModified: lastModified, etag: "W/\"abc\"", pollInterval: 60,
            body: try! JSONSerialization.data(withJSONObject: threads)
        )
    }

    static func primed() -> ChangeFeed {
        var feed = ChangeFeed()
        _ = feed.absorb(ok([thread()]), watching: [])
        return feed
    }

    @Test func theFirstAnswerOnlySetsTheBaseline() {
        var feed = ChangeFeed()
        #expect(feed.absorb(Self.ok([Self.thread()]), watching: []) == .quiet)
        #expect(feed.conditionalHeaders == [
            "If-Modified-Since": "Fri, 02 Oct 2026 18:00:00 GMT",
            "If-None-Match": "W/\"abc\"",
        ])
    }

    @Test func notModifiedDoesNothing() {
        var feed = Self.primed()
        let before = feed
        #expect(feed.absorb(.init(status: 304, pollInterval: 60), watching: []) == .unchanged)
        #expect(feed == before)
    }

    @Test func aNewerPullRequestYouAreInWakesTheSync() {
        var feed = Self.primed()
        let newer = Self.ok([Self.thread(updated: "2026-10-02T18:05:00Z"), Self.thread()])
        #expect(feed.absorb(newer, watching: []) == .wake)
        #expect(feed.absorb(newer, watching: []) == .quiet)
    }

    @Test func issuesAndOldThreadsStayQuiet() {
        var feed = Self.primed()
        #expect(feed.absorb(Self.ok([Self.thread(type: "Issue", updated: "2026-10-02T19:00:00Z")]), watching: []) == .quiet)
        #expect(feed.absorb(Self.ok([Self.thread(updated: "2026-10-02T17:00:00Z")]), watching: []) == .quiet)
    }

    @Test func subscribedActivityWakesOnlyForWatchedRepos() {
        let busy = Self.ok([Self.thread("acme/web", reason: "subscribed", updated: "2026-10-02T19:00:00Z")])
        var feed = Self.primed()
        #expect(feed.absorb(busy, watching: []) == .quiet)
        feed = Self.primed()
        #expect(feed.absorb(busy, watching: ["acme/web"]) == .wake)
    }

    @Test func mutedReposNeverWake() {
        var feed = Self.primed()
        let muted = Self.ok([Self.thread("acme/noisy", updated: "2026-10-02T19:00:00Z")])
        #expect(feed.absorb(muted, watching: ["acme/noisy"], muted: ["acme/noisy"]) == .quiet)
    }

    @Test(arguments: [401, 403, 404])
    func aTokenWithoutNotificationsTurnsTheFeedOff(status: Int) {
        var feed = Self.primed()
        #expect(feed.absorb(.init(status: status), watching: []) == .off)
        #expect(feed.isOff)
    }

    @Test func serverErrorsKeepPolling() {
        var feed = Self.primed()
        #expect(feed.absorb(.init(status: 502), watching: []) == .quiet)
        #expect(!feed.isOff)
    }

    @Test func pollIntervalNeverGoesBelowAMinute() {
        var feed = ChangeFeed()
        _ = feed.absorb(.init(status: 304, pollInterval: 120), watching: [])
        #expect(feed.interval == 120)
        _ = feed.absorb(.init(status: 304, pollInterval: 5), watching: [])
        #expect(feed.interval == 60)
    }

    @Test func theRequestIsConditionalAndBypassesTheLocalCache() async throws {
        let transport = StubTransport { _ in .init(status: 304, headers: ["X-Poll-Interval": "90"]) }
        let client = GitHubClient(transport: transport, tokens: CountingTokens(), retryDelays: [])
        let reply = try await client.notifications(Self.primed())
        #expect(reply.status == 304)
        #expect(reply.pollInterval == 90)
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/notifications?per_page=5")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Fri, 02 Oct 2026 18:00:00 GMT")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "W/\"abc\"")
    }

    @Test func anExpiredTokenIsRefreshedOnce() async throws {
        let tokens = CountingTokens()
        let transport = StubTransport { _ in .init(status: 401) }
        let client = GitHubClient(transport: transport, tokens: CachedTokenSource(tokens), retryDelays: [])
        let reply = try await client.notifications(ChangeFeed())
        #expect(reply.status == 401)
        #expect(transport.requests.count == 2)
        #expect(tokens.count == 2)
    }

    @MainActor
    @Test func aWakeRunsTheQueueSync() async throws {
        let github = FakeGitHub(.realistic())
        let notifications = Notifications()
        github.transport.respond { query in
            query.isEmpty ? notifications.reply : github.reply(query)
        }
        let model = AppModel(
            client: GitHubClient(transport: github.transport, tokens: CachedTokenSource(CountingTokens()), retryDelays: []),
            store: Store(directory: StoreDiffTests.tempDirectory())
        )
        await model.refresh()

        notifications.reply = .init(status: 200, body: try JSONSerialization.data(withJSONObject: [Self.thread()]))
        var before = github.transport.queries.count
        #expect(await model.pollFeed())
        #expect(FakeGitHub.syncKinds(github.transport.queries.dropFirst(before)).isEmpty)

        notifications.reply = .init(status: 304)
        before = github.transport.queries.count
        #expect(await model.pollFeed())
        #expect(FakeGitHub.syncKinds(github.transport.queries.dropFirst(before)).isEmpty)

        let newer = Self.thread(updated: "2026-10-02T18:05:00Z")
        notifications.reply = .init(status: 200, body: try JSONSerialization.data(withJSONObject: [newer]))
        before = github.transport.queries.count
        #expect(await model.pollFeed())
        #expect(FakeGitHub.syncKinds(github.transport.queries.dropFirst(before)) == ["beat", "beat", "beat"])

        notifications.reply = .init(status: 403)
        #expect(await model.pollFeed() == false)
        #expect(model.feed.isOff)
    }

    final class Notifications: @unchecked Sendable {
        private let lock = NSLock()
        private var current = StubTransport.Reply(status: 304)
        var reply: StubTransport.Reply {
            get { lock.withLock { current } }
            set { lock.withLock { current = newValue } }
        }
    }
}
