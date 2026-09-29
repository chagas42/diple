import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct RewardsTests {
    @Test func everyRarityHasAnArtifact() {
        for r in Rarity.allCases {
            #expect(Artifact.catalog.contains { $0.rarity == r })
        }
    }

    @Test func everySpriteIsSixteenBySixteenAndFullyColoured() {
        for a in Artifact.catalog {
            #expect(a.pixels.count == 16)
            for row in a.pixels {
                #expect(row.count == 16)
                #expect(row.allSatisfy { $0 == "." || a.palette[$0] != nil })
            }
        }
    }

    @Test func theLowestRollIsCommonAndTheHighestLegendary() {
        #expect(Artifact.roll(fast: false, dice: { 0 }).rarity == .common)
        #expect(Artifact.roll(fast: false, dice: { 0.9999 }).rarity == .legendary)
    }

    @Test func aFastReviewMakesRareOrBetterMoreLikely() {
        let steps = (0..<1000).map { Double($0) / 1000 }
        func rareShare(_ fast: Bool) -> Int {
            steps.filter { d in Artifact.roll(fast: fast, dice: { d }).rarity >= .rare }.count
        }
        #expect(rareShare(true) > rareShare(false))
    }

    static func queue(_ world: FakeWorld) async throws -> Queue {
        let client = GitHubClient(transport: StubTransport(body: world.queueResponse()), tokens: CountingTokens(), metrics: Metrics())
        return try await client.fetchQueue()
    }

    @Test func aRequestThatLeavesTheListIsACandidateSinceItWasFirstSeen() async throws {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        var world = FakeWorld.realistic()
        _ = store.diff(try await Self.queue(world), meuLogin: "you")
        world.toReview.append(FakeWorld.pr(40, author: "newcomer", viewer: "you"))
        _ = store.diff(try await Self.queue(world), meuLogin: "you")
        let key = try #require(store.state.requestSeenAt.keys.first)
        let seen = try #require(store.state.requestSeenAt[key])
        #expect(store.unrequested.isEmpty)

        world.toReview.removeLast()
        _ = store.diff(try await Self.queue(world), meuLogin: "you")
        #expect(store.unrequested == [Store.Unrequested(key: key, since: seen)])
        #expect(store.state.requestSeenAt[key] == nil)
    }

    @Test func collectingCountsEachArtifact() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        store.collect(.sample(.rare))
        store.collect(.sample(.rare))
        #expect(store.state.artifacts[Artifact.sample(.rare).id] == 2)
    }

    final class Gate {
        var waiting: [CheckedContinuation<Void, Never>] = []
        func open() { let w = waiting; waiting = []; w.forEach { $0.resume() } }
    }

    func notch(full: StoreFlag = StoreFlag(false), gate: Gate? = nil) -> NotchController {
        let n = NotchController()
        n.wakes = false
        n.fullScreen = { full.on }
        n.pointer = { CGPoint(x: -1000, y: -1000) }
        if let gate { n.nap = { _ in await withCheckedContinuation { gate.waiting.append($0) } } }
        n.settleBeforeFirstFrame()
        return n
    }

    static func reward(_ r: Rarity, _ id: String = "r") -> Reward {
        Reward(id: id, artifact: .sample(r), pr: "o/r#1")
    }

    @Test func aReviewCelebratesWithoutGrowingTheNotch() {
        let n = notch(gate: Gate())
        n.reward(Self.reward(.epic))
        #expect(n.state == .active)
        #expect(n.celebration == .epic)
        #expect(n.unclaimed.map(\.id) == ["r"])
    }

    @Test func overAFullScreenAppTheCelebrationWaitsForTheNotchToComeBack() {
        let full = StoreFlag(true)
        let n = notch(full: full, gate: Gate())
        n.reward(Self.reward(.rare))
        #expect(n.state == .hidden)
        #expect(n.celebration == nil)
        #expect(n.pendingCelebrations == [.rare])

        full.on = false
        n.refreshIdle()
        #expect(n.celebration == .rare)
    }

    @Test func celebrationsPlayOneAtATime() async {
        let gate = Gate()
        let n = notch(gate: gate)
        n.reward(Self.reward(.common, "a"))
        n.reward(Self.reward(.legendary, "b"))
        #expect(n.celebration == .common)
        for _ in 0..<4 {
            while gate.waiting.isEmpty { await Task.yield() }
            gate.open()
        }
        while n.celebration != .legendary { await Task.yield() }
        #expect(n.unclaimed.map(\.id) == ["a", "b"])
    }
}

final class StoreFlag {
    var on: Bool
    init(_ on: Bool) { self.on = on }
}
