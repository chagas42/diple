import Foundation
import Testing
@testable import Diple

final class Source: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var values: [Int]
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ values: [Int]) { self.values = values }

    var count: Int { lock.withLock { calls } }

    func hold() { lock.withLock { held = true } }

    func release() {
        let resumed = lock.withLock {
            held = false
            defer { waiting = [] }
            return waiting
        }
        for c in resumed { c.resume() }
    }

    func next() async -> Int {
        let (value, mustWait) = lock.withLock {
            calls += 1
            return (values.count > 1 ? values.removeFirst() : values[0], held)
        }
        if mustWait {
            await withCheckedContinuation { c in
                let resumeNow = lock.withLock {
                    guard held else { return true }
                    waiting.append(c)
                    return false
                }
                if resumeNow { c.resume() }
            }
        }
        return value
    }
}

@MainActor
@Suite struct QueryClientTests {
    static let github = GitHubClient(
        transport: StubTransport(body: Data()), tokens: CountingTokens(), retryDelays: []
    )

    static func query(
        _ source: Source, key: QueryKey = .repos,
        tags: [QueryTag] = [], staleAfter: Duration = .seconds(60),
        forgetAfter: Duration = .seconds(300), persists: Bool = false
    ) -> CacheQuery<Int> {
        CacheQuery(
            key: key, tags: tags, staleAfter: staleAfter, forgetAfter: forgetAfter, persists: persists
        ) { _ in await source.next() }
    }

    static func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func twoIdenticalRequestsShareOneFetch() async throws {
        let client = QueryClient(github: Self.github)
        let source = Source([1])
        source.hold()
        let q = Self.query(source)
        async let a = client.fetch(q)
        async let b = client.fetch(q)
        try await Self.until { source.count > 0 }
        source.release()
        #expect(try await [a, b] == [1, 1])
        #expect(source.count == 1)
    }

    @Test func freshDataIsServedWithoutAFetch() async throws {
        let client = QueryClient(github: Self.github)
        let source = Source([1, 2])
        let q = Self.query(source)
        _ = try await client.fetch(q)
        #expect(try await client.fetch(q) == 1)
        #expect(source.count == 1)
    }

    @Test func staleDataIsFetchedAgain() async throws {
        var clock = Date(timeIntervalSince1970: 0)
        let client = QueryClient(github: Self.github, now: { clock })
        let source = Source([1, 2])
        let q = Self.query(source, staleAfter: .seconds(60))
        _ = try await client.fetch(q)
        clock += 61
        #expect(try await client.fetch(q) == 2)
    }

    @Test func aReplyAfterItsDataWasClearedIsDropped() async throws {
        let client = QueryClient(github: Self.github)
        let source = Source([1, 2])
        source.hold()
        let q = Self.query(source, tags: [.pr("acme/app#1")])
        let late = Task { try await client.fetch(q) }
        try await Self.until { source.count == 1 }
        client.invalidate(.pr("acme/app#1"))
        let fresh = Task { try await client.fetch(q) }
        try await Self.until { source.count == 2 }
        source.release()
        #expect(try await late.value == 2)
        #expect(try await fresh.value == 2)
        #expect(try await client.fetch(q) == 2)
    }

    @Test func oldDataShowsWhileNewDataLoads() async throws {
        let client = QueryClient(github: Self.github)
        let source = Source([1, 2])
        let q = Self.query(source)
        let observer = client.observe(q)
        try await Self.until { observer.data == 1 && !observer.isFetching }
        source.hold()
        let refetch = Task { await observer.refetch() }
        try await Self.until { observer.isFetching }
        #expect(observer.data == 1)
        source.release()
        await refetch.value
        #expect(observer.data == 2)
        #expect(!observer.isFetching)
    }

    @Test func clearingATagRefetchesOnlyWhatIsVisible() async throws {
        let client = QueryClient(github: Self.github)
        let shown = Source([1, 2])
        let hidden = Source([10, 20])
        let other = Source([100, 200])
        let observer = client.observe(Self.query(shown, key: .repoPRs(repo: "acme/app"), tags: [.repo("acme/app")]))
        let hiddenQuery = Self.query(hidden, key: .repoPRs(repo: "acme/lib"), tags: [.repo("acme/app")])
        _ = try await client.fetch(hiddenQuery)
        let otherObserver = client.observe(Self.query(other, key: .team(org: "acme"), tags: [.team]))
        try await Self.until { observer.data == 1 && otherObserver.data == 100 }

        client.invalidate(.repo("acme/app"))
        try await Self.until { observer.data == 2 }
        #expect(hidden.count == 1)
        #expect(other.count == 1)
        #expect(try await client.fetch(hiddenQuery) == 20)
    }

    @Test func aFailedFetchKeepsTheOldData() async throws {
        struct Boom: Error {}
        let client = QueryClient(github: Self.github)
        let fails = Locked(false)
        let q = CacheQuery<Int>(key: .repos, staleAfter: .zero) { _ in
            if fails.value { throw Boom() }
            return 1
        }
        let observer = client.observe(q)
        try await Self.until { observer.data == 1 }
        fails.value = true
        await observer.refetch()
        #expect(observer.data == 1)
        #expect(observer.error is Boom)
    }

    @Test func setDataPatchesInPlace() async throws {
        let client = QueryClient(github: Self.github)
        let source = Source([1])
        let observer = client.observe(Self.query(source))
        try await Self.until { observer.data == 1 }
        client.setData(.repos) { (n: inout Int) in n += 41 }
        #expect(observer.data == 42)
        #expect(source.count == 1)
    }

    @Test func unobservedDataIsForgotten() async throws {
        let client = QueryClient(github: Self.github)
        let source = Source([1, 2])
        let q = Self.query(source, forgetAfter: .milliseconds(20))
        var observer: QueryObserver<Int>? = client.observe(q)
        try await Self.until { observer?.data == 1 }
        observer = nil
        try await Self.until { client.cached(.repos, as: Int.self) == nil }
        #expect(try await client.fetch(q) == 2)
    }

    @Test func persistedDataIsReadBackAtLaunch() async throws {
        let dir = StoreDiffTests.tempDirectory()
        let store = Store(directory: dir, metrics: Metrics(), debounce: .milliseconds(10))
        let source = Source([7])
        _ = try await QueryClient(github: Self.github, store: store).fetch(Self.query(source, persists: true))
        await store.settle()

        let relaunched = QueryClient(github: Self.github, store: Store(directory: dir, metrics: Metrics()))
        #expect(try await relaunched.fetch(Self.query(source, persists: true)) == 7)
        #expect(source.count == 1)
    }

    @Test func onlyPersistedQueriesReachTheDisk() async throws {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        _ = try await QueryClient(github: Self.github, store: store).fetch(Self.query(Source([7])))
        #expect(store.state.cache.queries == nil)
    }

    @Test func nothingIsWrittenWhenDataIsUnchanged() async throws {
        var clock = Date(timeIntervalSince1970: 0)
        let metrics = Metrics()
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: metrics, debounce: .milliseconds(10))
        let client = QueryClient(github: Self.github, store: store, now: { clock })
        let q = Self.query(Source([7]), staleAfter: .seconds(60), persists: true)
        _ = try await client.fetch(q)
        await store.settle()
        #expect(metrics.snapshot().count(.storeWrites) == 1)
        for _ in 0..<5 {
            clock += 10
            _ = try await client.fetch(q, force: true)
            await store.settle()
        }
        #expect(metrics.snapshot().count(.storeWrites) == 1)
    }

    @Test func aStaleRefetchOfTheSameDataRecordsWhenItWasConfirmed() async throws {
        var clock = Date(timeIntervalSince1970: 0)
        let dir = StoreDiffTests.tempDirectory()
        let store = Store(directory: dir, metrics: Metrics(), debounce: .milliseconds(10))
        let client = QueryClient(github: Self.github, store: store, now: { clock })
        let source = Source([7])
        let q = Self.query(source, staleAfter: .seconds(60), persists: true)
        _ = try await client.fetch(q)
        clock += 61
        _ = try await client.fetch(q)
        await store.settle()

        let relaunched = QueryClient(github: Self.github, store: Store(directory: dir, metrics: Metrics()), now: { clock })
        #expect(try await relaunched.fetch(q) == 7)
        #expect(source.count == 2)
    }

    @Test func savedRowsPastTheirForgetTimeArePrunedAtLaunch() async throws {
        let dir = StoreDiffTests.tempDirectory()
        let store = Store(directory: dir, metrics: Metrics(), debounce: .milliseconds(10))
        let client = QueryClient(github: Self.github, store: store)
        _ = try await client.fetch(Self.query(Source([7]), key: .team(org: "old"), forgetAfter: .seconds(1), persists: true))
        await store.settle()
        #expect(store.state.cache.queries?[QueryKey.team(org: "old").id] != nil)

        let later = Store(directory: dir, metrics: Metrics())
        _ = QueryClient(github: Self.github, store: later, now: { Date().addingTimeInterval(10) })
        #expect(later.state.cache.queries?[QueryKey.team(org: "old").id] == nil)
    }

    @Test func anUnobservedEntryClearedMidFetchIsStillForgotten() async throws {
        let client = QueryClient(github: Self.github)
        let source = Source([1, 2])
        let q = Self.query(source, tags: [.team], staleAfter: .zero, forgetAfter: .milliseconds(10))
        _ = try await client.fetch(q)
        source.hold()
        client.prefetch(q)
        try await Self.until { source.count == 2 }
        client.invalidate(.team)
        source.release()
        try await Self.until { client.cached(.repos, as: Int.self) == nil }
        #expect(client.cached(.repos, as: Int.self) == nil)
    }

    final class Box: Sendable, Equatable {
        let value: Int
        init(_ value: Int) { self.value = value }
        static func == (a: Box, b: Box) -> Bool { a.value == b.value }
    }

    @Test func refetchingEqualDataKeepsWhatIsOnScreen() async throws {
        let client = QueryClient(github: Self.github)
        let q = CacheQuery<Box>(key: .repos, staleAfter: .zero) { _ in Box(1) }
        let observer = client.observe(q)
        try await Self.until { observer.data != nil && !observer.isFetching }
        let shown = try #require(observer.data)
        await observer.refetch()
        #expect(observer.data === shown)
    }

    @Test func successRunsOnceForJoinedRequestsAndNeverForADroppedReply() async throws {
        let client = QueryClient(github: Self.github)
        let source = Source([1, 2])
        source.hold()
        let successes = Locked<[Int]>([])
        var q = Self.query(source, tags: [.team])
        q.onSuccess = { successes.value.append($0) }
        let a = Task { try await client.fetch(q) }
        let b = Task { try await client.fetch(q) }
        try await Self.until { source.count == 1 }
        client.invalidate(.team)
        let c = Task { try await client.fetch(q) }
        try await Self.until { source.count == 2 }
        source.release()
        _ = try await (a.value, b.value, c.value)
        #expect(successes.value == [2])
    }

    @Test func aHeldResultOutlivesItsForgetTime() async throws {
        let client = QueryClient(github: Self.github)
        let key = QueryKey.aiReview(pr: "acme/app#1", revision: "abc")
        let hold = client.hold(key)
        client.put(key, 42, forgetAfter: .milliseconds(10))
        try await Task.sleep(for: .milliseconds(60))
        #expect(client.cached(key, as: Int.self) == 42)
        withExtendedLifetime(hold) {}
    }

    @Test func aNewKeyCanShowThePreviousDataWhileItLoads() async throws {
        let client = QueryClient(github: Self.github)
        let source = Source([2])
        source.hold()
        let observer = client.observe(Self.query(source, key: .team(org: "b")), placeholder: 1)
        #expect(observer.data == 1)
        #expect(observer.isFetching && observer.isLoading)
        source.release()
        try await Self.until { !observer.isFetching }
        #expect(observer.data == 2)
    }

    @Test func keysCarryEverythingTheDataDependsOn() {
        let before = QueryKey.ranking(org: "acme", period: .week, people: ["ana", "bia"])
        let after = QueryKey.ranking(org: "acme", period: .week, people: ["ana"])
        #expect(before != after)
        #expect(before.id != after.id)
        #expect(QueryKey.queue(watching: ["b", "a"]).id == QueryKey.queue(watching: ["a", "b"]).id)
    }
}

final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
