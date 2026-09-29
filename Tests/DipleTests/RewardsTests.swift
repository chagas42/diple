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

    @Test func collectingCountsEachArtifactAndTheReviewsOfTheDay() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        #expect(store.collect(.sample(.rare), on: "2026-09-29") == 1)
        #expect(store.collect(.sample(.rare), on: "2026-09-29") == 2)
        #expect(store.state.artifacts[Artifact.sample(.rare).id] == 2)
        #expect(store.collect(.sample(.common), on: "2026-09-30") == 1)
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

    @Test func githubReviewStatesReadAsVerdicts() {
        #expect(ReviewVerdict(github: "APPROVED") == .approved)
        #expect(ReviewVerdict(github: "CHANGES_REQUESTED") == .changesRequested)
        #expect(ReviewVerdict(github: "COMMENTED") == .commented)
        #expect(ReviewVerdict(github: nil) == .commented)
    }

    @Test func aReviewOpensADrawerUnderTheNotchAndClosesIt() async {
        let gate = Gate()
        let n = notch(gate: gate)
        let resting = NotchGeometry.current().active
        n.reward(Self.reward(.epic))
        #expect(n.state == .active)
        #expect(n.size.height == resting.height + MarginMark.drawer)
        #expect(n.size.width > resting.width)
        for _ in 0..<3 {
            while gate.waiting.isEmpty { await Task.yield() }
            gate.open()
        }
        while n.celebration != nil { await Task.yield() }
        #expect(n.size == resting)
    }

    @Test func aReviewCelebratesInTheIdleNotch() {
        let n = notch(gate: Gate())
        n.reward(Self.reward(.epic))
        #expect(n.state == .active)
        #expect(n.celebration?.artifact.rarity == .epic)
        #expect(n.unclaimed.map(\.id) == ["r"])
    }

    @Test func overAFullScreenAppTheCelebrationWaitsForTheNotchToComeBack() {
        let full = StoreFlag(true)
        let n = notch(full: full, gate: Gate())
        n.reward(Self.reward(.rare))
        #expect(n.state == .hidden)
        #expect(n.celebration == nil)
        #expect(n.pendingCelebrations.map(\.artifact.rarity) == [.rare])

        full.on = false
        n.refreshIdle()
        #expect(n.celebration?.artifact.rarity == .rare)
    }

    @Test func celebrationsPlayOneAtATime() async {
        let gate = Gate()
        let n = notch(gate: gate)
        n.reward(Self.reward(.common, "a"))
        n.reward(Self.reward(.legendary, "b"))
        #expect(n.celebration?.artifact.rarity == .common)
        for _ in 0..<6 {
            while gate.waiting.isEmpty { await Task.yield() }
            gate.open()
        }
        while n.celebration?.artifact.rarity != .legendary { await Task.yield() }
        #expect(n.unclaimed.map(\.id) == ["a", "b"])
    }

    @Test func withAGoalTheTallyCountsTowardsItAndTheBarShowsTheDay() {
        var r = Self.reward(.rare)
        r.today = 2
        r.goal = 3
        #expect(MarginMark.tally(r) == "+1 · 2/3 today")
        #expect(abs(MarginMark.fill(r, 0) - 1.0 / 3) < 0.001)
        #expect(abs(MarginMark.fill(r, 1) - 2.0 / 3) < 0.001)
        r.today = 3
        #expect(MarginMark.tally(r) == "+1 · daily goal \u{2713}")
        #expect(MarginMark.fill(r, 1) == 1)
        r.goal = nil
        #expect(MarginMark.tally(r) == "+1 · 3 today")
        #expect(MarginMark.fill(r, 0.4) == 0.4)
    }

    @Test func earnedArtifactsAreKeptAndMarkedWhenClaimed() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        let e = EarnedArtifact(id: "x", artifact: "floppy", pr: "o/r#1", verdict: .approved, at: Date())
        store.collect(.sample(.uncommon), on: "2026-09-29", record: e)
        #expect(store.state.earned.map(\.id) == ["x"])
        #expect(store.state.earned.first?.claimedAt == nil)
        store.markClaimed("x")
        #expect(store.state.earned.first?.claimedAt != nil)
    }

    @Test func wantingToUnblockTheTeamRewardsSpeedMore() {
        let steps = (0..<1000).map { Double($0) / 1000 }
        func rare(_ boost: Double) -> Int {
            steps.filter { d in Artifact.roll(fast: true, boost: boost, dice: { d }).rarity >= .rare }.count
        }
        #expect(RewardsProfile(reason: .unblock).fastBoost == 3)
        #expect(RewardsProfile(reason: .learn).fastBoost == 2)
        #expect(rare(3) > rare(2))
    }

    @Test func whileClaimingHoveringTheNotchDoesNotOpenIt() {
        let n = notch(gate: Gate())
        n.reward(Self.reward(.rare))
        n.pointer = {
            let g = NotchGeometry.current()
            let r = g.rect(g.closed)
            return CGPoint(x: r.midX, y: r.midY)
        }
        var shown: [String] = []
        n.presentClaim = { r, _ in shown.append(r.id) }
        n.claim()
        #expect(shown == ["r"])
        n.checkPointer()
        #expect(n.state != .open)
        #expect(n.claiming)
    }
}

final class StoreFlag {
    var on: Bool
    init(_ on: Bool) { self.on = on }
}