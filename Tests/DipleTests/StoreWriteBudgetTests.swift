import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct StoreWriteBudgetTests {
    static func store(_ dir: URL = StoreDiffTests.tempDirectory(), metrics: Metrics) -> Store {
        Store(directory: dir, metrics: metrics, debounce: .milliseconds(150))
    }

    @Test func aBurstOfChangesIsOneWrite() async throws {
        let metrics = Metrics()
        let store = Self.store(metrics: metrics)
        for i in 0..<100 { store.toggleFollow("person\(i)") }
        await store.settle()
        #expect((1...2).contains(metrics.snapshot().count(.storeWrites)))
    }

    @Test func theDebounceWritesOnItsOwn() async throws {
        let metrics = Metrics()
        let store = Self.store(metrics: metrics)
        store.toggleFollow("someone")
        let deadline = ContinuousClock.now + .seconds(15)
        while metrics.snapshot().count(.storeWrites) == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(metrics.snapshot().count(.storeWrites) == 1)
    }

    @Test func nothingChangedIsNoWrite() async {
        let metrics = Metrics()
        let store = Self.store(metrics: metrics)
        store.toggleFollow("a")
        store.toggleFollow("a")
        await store.settle()
        #expect(metrics.snapshot().count(.storeWrites) == 0)
    }

    @Test func aSteadyRefreshDoesNotTouchTheDisk() async throws {
        let metrics = Metrics()
        let store = Self.store(metrics: metrics)
        let q = try await StoreDiffTests.queue(.realistic())
        _ = store.diff(q, meuLogin: "you")
        await store.settle()
        #expect(metrics.snapshot().count(.storeWrites) == 1)
        for _ in 0..<5 {
            _ = store.diff(q, meuLogin: "you")
            await store.settle()
        }
        #expect(metrics.snapshot().count(.storeWrites) == 1)
    }

    @Test func aNewRateLimitAloneIsNoWrite() async throws {
        let metrics = Metrics()
        let store = Self.store(metrics: metrics)
        var q = try await StoreDiffTests.queue(.realistic())
        store.saveQueue(q)
        await store.settle()
        q.rateLimitLeft -= 1
        store.saveQueue(q)
        await store.settle()
        #expect(metrics.snapshot().count(.storeWrites) == 1)
    }

    @Test func writesNeverRunOnTheMainThread() async throws {
        let metrics = Metrics()
        let store = Self.store(metrics: metrics)
        _ = store.diff(try await StoreDiffTests.queue(.realistic()), meuLogin: "you")
        store.toggleWatch("acme/repo1")
        await store.settle()
        #expect(metrics.snapshot().count(.storeWrites) >= 1)
        #expect(metrics.snapshot().count(.storeWritesOnMain) == 0)
    }

    @Test func settledStateSurvivesAReload() async {
        let dir = StoreDiffTests.tempDirectory()
        let store = Self.store(dir, metrics: Metrics())
        store.toggleFollow("marina")
        await store.settle()
        #expect(Self.store(dir, metrics: Metrics()).state.following == ["marina"])
    }

    @Test func flushNowPersistsBeforeReturning() {
        let dir = StoreDiffTests.tempDirectory()
        let store = Self.store(dir, metrics: Metrics())
        store.toggleFollow("rafael")
        store.flushNow()
        #expect(Self.store(dir, metrics: Metrics()).state.following == ["rafael"])
    }

    @Test func aLateOlderSnapshotNeverOverwritesANewerOne() async throws {
        let dir = StoreDiffTests.tempDirectory()
        let store = Self.store(dir, metrics: Metrics())
        store.toggleFollow("first")
        store.toggleFollow("second")
        store.flushNow()
        try await Task.sleep(for: .milliseconds(400))
        #expect(Self.store(dir, metrics: Metrics()).state.following == ["first", "second"])
    }
}
