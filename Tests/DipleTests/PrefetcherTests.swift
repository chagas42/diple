import Foundation
import Testing
@testable import Diple

final class ReviewGitHub: @unchecked Sendable {
    let github = FakeGitHub(.realistic())
    private(set) var transport: StubTransport!
    private let lock = NSLock()
    private var delay: Duration = .zero
    private var refFetches: [Int] = []

    init() {
        transport = StubTransport { [self] q in self.reply(q) }
    }

    func delay(_ d: Duration) { lock.withLock { delay = d } }
    var fetchedRefs: [Int] { lock.withLock { refFetches } }

    var fetchRefs: Prefetcher.FetchRefs {
        { [self] _, pr, _ in self.lock.withLock { self.refFetches.append(pr) } }
    }

    static func kind(_ q: String) -> String {
        if q.contains("reviewThreads(first: 100)") { return "context" }
        if q.contains("files(first: 100") { return "files" }
        return FakeGitHub.kind(q)
    }

    private func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }

    private func reply(_ q: String) -> StubTransport.Reply {
        let d = lock.withLock { delay }
        switch Self.kind(q) {
        case "context":
            let pull: [String: Any] = [
                "baseRefOid": "base000", "headRefOid": "head111", "body": "why",
                "author": ["login": "teammate", "__typename": "User"],
                "reviewThreads": ["nodes": []], "comments": ["nodes": []], "reviews": ["nodes": []],
            ]
            return .init(body: json(["data": ["repository": ["pullRequest": pull]]]), delay: d)
        case "files":
            let pull: [String: Any] = [
                "baseRefOid": "base000", "headRefOid": "head111",
                "files": ["pageInfo": ["hasNextPage": false, "endCursor": NSNull()],
                          "nodes": [["path": "src/a.ts", "additions": 3, "deletions": 1]]],
            ]
            return .init(body: json(["data": ["repository": ["pullRequest": pull]]]), delay: d)
        default:
            return github.reply(q)
        }
    }

    func prs() async throws -> [PR] {
        try await GitHubClient(transport: transport, tokens: CountingTokens(), metrics: Metrics()).fetchQueue().mine
    }

    func othersPRs() async throws -> [PR] {
        try await GitHubClient(transport: transport, tokens: CountingTokens(), metrics: Metrics()).fetchQueue().toReview
    }
}

@MainActor
@Suite struct PrefetcherTests {
    static func rig() -> (ReviewGitHub, Prefetcher) {
        let gh = ReviewGitHub()
        let client = GitHubClient(transport: gh.transport, tokens: CountingTokens(), metrics: Metrics())
        return (gh, Prefetcher(queries: QueryClient(github: client), fetchRefs: gh.fetchRefs))
    }

    static func count(_ gh: ReviewGitHub, _ kind: String) -> Int {
        gh.transport.queries.filter { ReviewGitHub.kind($0) == kind }.count
    }

    @Test func aWarmedPullRequestNeedsNoRequestToStartItsReview() async throws {
        let (gh, prefetcher) = Self.rig()
        let pr = try await gh.prs()[0]
        await prefetcher.warm([.init(pr: pr, origin: nil)])
        let context = await prefetcher.context(for: pr)
        #expect(context?.head == "head111")
        let value1 = await prefetcher.changedFiles(for: pr)?.files.count
        #expect(value1 == 1)
    }

    @Test func warmingTwiceFetchesOnce() async throws {
        let (gh, prefetcher) = Self.rig()
        let prs = try await gh.prs()
        let targets = prs.map { Prefetcher.Target(pr: $0, origin: nil) }
        await prefetcher.warm(targets)
        let after = gh.transport.queries.count
        await prefetcher.warm(targets)
        #expect(gh.transport.queries.count == after)
    }

    @Test func aNewerPullRequestIsNotServedAnOldContext() async throws {
        let (gh, prefetcher) = Self.rig()
        let pr = try await gh.prs()[0]
        await prefetcher.warm([.init(pr: pr, origin: nil)])
        gh.github.edit { w in w.update(pr.id) { $0.updatedAt = $0.updatedAt.addingTimeInterval(60) } }
        let newer = try await gh.prs()[0]
        let value2 = await prefetcher.context(for: newer)
        #expect(value2 == nil)
        await prefetcher.warm([.init(pr: newer, origin: nil)])
        let value3 = await prefetcher.context(for: newer)
        #expect(value3 != nil)
        #expect(Self.count(gh, "context") == 2)
    }

    @Test func refsAreFetchedOnlyForLocalRepositoriesAndOnlyOnce() async throws {
        let (gh, prefetcher) = Self.rig()
        let prs = try await gh.prs()
        let local = URL(fileURLWithPath: "/tmp/nowhere")
        await prefetcher.warm([.init(pr: prs[0], origin: local), .init(pr: prs[1], origin: nil)])
        await prefetcher.warm([.init(pr: prs[0], origin: local)])
        #expect(gh.fetchedRefs == [prs[0].number])
    }

    @Test func aFailedWarmIsNotRetriedUntilThePullRequestChanges() async throws {
        let (gh, prefetcher) = Self.rig()
        let pr = try await gh.prs()[0]
        let broken = StubTransport { _ in .init(status: 502) }
        let failing = Prefetcher(
            queries: QueryClient(github: GitHubClient(
                transport: broken, tokens: CountingTokens(), metrics: Metrics(), retryDelays: [.zero, .zero]
            )),
            fetchRefs: gh.fetchRefs
        )
        await failing.warm([.init(pr: pr, origin: nil)])
        let after = broken.queries.count
        await failing.warm([.init(pr: pr, origin: nil)])
        #expect(broken.queries.count == after)
        _ = prefetcher
    }

    @Test func someoneElsesPullRequestGetsItsFilesButNoReviewContext() async throws {
        let (gh, prefetcher) = Self.rig()
        let theirs = try await gh.othersPRs()[0]
        await prefetcher.warm([.init(pr: theirs, origin: URL(fileURLWithPath: "/tmp/nowhere"))])
        #expect(await prefetcher.context(for: theirs) == nil)
        #expect(await prefetcher.changedFiles(for: theirs) != nil)
        #expect(Self.count(gh, "context") == 0)
        #expect(gh.fetchedRefs == [theirs.number])
    }

    @Test func noMoreThanThreePullRequestsWarmAtOnce() async throws {
        let (gh, prefetcher) = Self.rig()
        let prs = Array(try await gh.prs().prefix(8))
        gh.delay(.milliseconds(60))
        gh.transport.resetPeak()
        await prefetcher.warm(prs.map { .init(pr: $0, origin: nil) })
        #expect(prs.count == 8)
        #expect(Self.count(gh, "context") == 8)
        #expect(gh.transport.peakConcurrency <= 6)
        #expect(gh.transport.peakConcurrency >= 4)
    }
}

@MainActor
@Suite struct PrefetchIntegrationTests {
    @Test func startingAReviewWhileItsContextIsPrefetchingSharesTheRequest() async throws {
        let gh = ReviewGitHub()
        let model = AppModel(
            client: GitHubClient(transport: gh.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics()),
            fetchRefs: gh.fetchRefs
        )
        let pr = try await gh.prs()[0]
        gh.delay(.milliseconds(150))
        let warming = Task { await model.prefetcher.warm([.init(pr: pr, origin: nil)]) }
        try await Task.sleep(for: .milliseconds(30))
        let context = try await model.reviewContext(for: pr)
        await warming.value
        #expect(context.head == "head111")
        #expect(PrefetcherTests.count(gh, "context") == 1)
    }

    @Test func aRefreshWarmsWhatNeedsYouForTheMapButNotForAReview() async throws {
        let gh = ReviewGitHub()
        let client = GitHubClient(transport: gh.transport, tokens: CountingTokens(), metrics: Metrics())
        let model = AppModel(
            client: client,
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics()),
            fetchRefs: gh.fetchRefs
        )
        model.preloadsTabs = false
        await model.refresh()
        await model.prefetchSettled()
        let first = try #require(model.needsYou.first)
        #expect(!first.isMine)
        let files = await model.prefetcher.changedFiles(for: first)
        let context = await model.prefetcher.context(for: first)
        #expect(files != nil)
        #expect(context == nil)
        #expect(PrefetcherTests.count(gh, "context") == 0)
        #expect(model.prefetchTargets().count == min(Prefetcher.depth, model.needsYou.count))
    }
}
