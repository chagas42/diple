import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct RewardsTests {
    @Test func everyRarityHasAnArtifact() {
        for r in Rarity.allCases {
            #expect(Artifact.catalog.contains { $0.rarity == r })
            #expect(Artifact.pick(r).rarity == r)
        }
    }

    @Test func everySpriteIsSixteenBySixteenAndFullyColoured() {
        for a in StickerSheet.everySticker {
            #expect(a.pixels.count == 16)
            for row in a.pixels {
                #expect(row.count == 16)
                #expect(row.allSatisfy { $0 == "." || a.palette[$0] != nil })
            }
        }
    }

    @Test func eachSeasonSheetGivesOneStickerPerMilestoneInRarityOrder() {
        for sheet in [StickerSheet.aiSeason, .devFolklore] {
            #expect(sheet.stickers.map(\.rarity) == Trail.rarities)
        }
        #expect(StickerSheet.of(season: "2026-Q3").id == "ai-season")
        #expect(StickerSheet.of(season: "2026-Q4").id == "dev-folklore")
        #expect(Set(StickerSheet.everySticker.map(\.id)).count == StickerSheet.everySticker.count)
    }

    @Test func githubReviewStatesReadAsVerdicts() {
        #expect(ReviewVerdict(github: "APPROVED") == .approved)
        #expect(ReviewVerdict(github: "CHANGES_REQUESTED") == .changesRequested)
        #expect(ReviewVerdict(github: "COMMENTED") == .commented)
        #expect(ReviewVerdict(github: nil) == .commented)
    }

    @Test func aSeasonIsAQuarter() {
        let cal = Calendar(identifier: .gregorian)
        func at(_ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: 15))! }
        #expect(Trail.season(of: at(1), calendar: cal) == "2026-Q1")
        #expect(Trail.season(of: at(9), calendar: cal) == "2026-Q3")
        #expect(Trail.season(of: at(10), calendar: cal) == "2026-Q4")
    }

    @Test func sixStickersAQuarterAtWideningMilestones() {
        #expect(Trail.milestones == [10, 30, 60, 100, 180, 300])
        #expect(Trail.milestone(at: 10) == 0)
        #expect(Trail.milestone(at: 11) == nil)
        #expect(Trail.rarities.last == .legendary)
        #expect(Trail.leg(for: 12)! == (10, 30))
        #expect(Trail.leg(for: 30)! == (10, 30))
        #expect(Trail.leg(for: 301) == nil)
    }

    static func tick(_ count: Int, sticker: Rarity? = nil, _ id: String = "t") -> ReviewTick {
        ReviewTick(id: id, pr: "acme/orders-api#7867", verdict: .approved, count: count,
                   reward: sticker.map { Reward(id: id, artifact: .sample($0), pr: "acme/orders-api#7867") })
    }

    @Test func theTrailFillsEvenlyBetweenMilestones() {
        #expect(CollectionView.trailFill(0) == 0)
        #expect(abs(CollectionView.trailFill(10) - 1.0 / 6) < 0.001)
        #expect(abs(CollectionView.trailFill(20) - 1.5 / 6) < 0.001)
        #expect(CollectionView.trailFill(300) == 1)
    }

    @Test func theStripSaysWhereYouAreOnTheLeg() {
        #expect(ReviewStrip.shortPR("acme/orders-api#7867") == "orders-api#7867")
        #expect(ReviewStrip.label(Self.tick(12)) == "12/30")
        #expect(abs(ReviewStrip.fill(Self.tick(12), 0) - 0.05) < 0.001)
        #expect(abs(ReviewStrip.fill(Self.tick(12), 1) - 0.10) < 0.001)
        #expect(ReviewStrip.fill(Self.tick(10), 1) == 1)
        #expect(ReviewStrip.label(Self.tick(320)) == "320 this season")
    }

    @Test func aReviewIsCountedOnceAndTheSeasonStartsOver() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        let at = Date()
        #expect(store.countReview("o/r#1", at: at, season: "2026-Q3") == 1)
        #expect(store.countReview("o/r#1", at: at, season: "2026-Q3") == nil)
        #expect(store.countReview("o/r#1", at: at.addingTimeInterval(600), season: "2026-Q3") == 2)
        #expect(store.countReview("o/r#2", at: at, season: "2026-Q4") == 1)
    }

    @Test func earnedStickersAreKeptAndMarkedWhenClaimed() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        let e = EarnedArtifact(id: "x", artifact: "floppy", pr: "o/r#1", verdict: .approved, at: Date())
        store.collect(.sample(.uncommon), on: "2026-09-29", record: e)
        #expect(store.state.artifacts["floppy"] == 1)
        #expect(store.state.earned.first?.claimedAt == nil)
        store.markClaimed("x")
        #expect(store.state.earned.first?.claimedAt != nil)
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

    func drain(_ gate: Gate, _ n: NotchController) async {
        while n.celebration != nil || !n.pendingCelebrations.isEmpty {
            if gate.waiting.isEmpty { await Task.yield() } else { gate.open() }
        }
    }

    @Test func aReviewOpensAThinStripAndClosesIt() async {
        let gate = Gate()
        let n = notch(gate: gate)
        let resting = NotchGeometry.current().active
        n.tick(Self.tick(12))
        #expect(n.celebration?.count == 12)
        #expect(n.size.height == resting.height + ReviewStrip.drawer)
        await drain(gate, n)
        #expect(n.size == resting)
        #expect(n.unclaimed.isEmpty)
    }

    @Test func onlyAMilestoneLeavesAStickerToClaim() async {
        let gate = Gate()
        let n = notch(gate: gate)
        n.tick(Self.tick(9, "a"))
        n.tick(Self.tick(10, sticker: .common, "b"))
        await drain(gate, n)
        #expect(n.unclaimed.map(\.id) == ["b"])
    }

    @Test func overAFullScreenAppTheStripWaitsForTheNotchToComeBack() {
        let full = StoreFlag(true)
        let n = notch(full: full, gate: Gate())
        n.tick(Self.tick(12))
        #expect(n.state == .hidden)
        #expect(n.celebration == nil)
        full.on = false
        n.refreshIdle()
        #expect(n.celebration?.count == 12)
    }

    @Test func tryingAStickerPlaysTheClaimWithoutAddingIt() {
        let n = notch(gate: Gate())
        var shown: [String] = []
        n.presentClaim = { r, _ in shown.append(r.artifact.id) }
        n.preview(Reward(id: "p", artifact: StickerSheet.aiSeason.stickers[5], pr: nil))
        #expect(shown == ["last-human-reviewer"])
        #expect(n.unclaimed.isEmpty)
        #expect(!n.claiming)
    }

    @Test func whileClaimingHoveringTheNotchDoesNotOpenIt() async {
        let gate = Gate()
        let n = notch(gate: gate)
        n.tick(Self.tick(10, sticker: .common))
        await drain(gate, n)
        n.pointer = {
            let g = NotchGeometry.current()
            let r = g.rect(g.closed)
            return CGPoint(x: r.midX, y: r.midY)
        }
        var shown: [String] = []
        n.presentClaim = { r, _ in shown.append(r.id) }
        n.claim()
        #expect(shown == ["t"])
        n.checkPointer()
        #expect(n.state != .open)
    }
}

final class StoreFlag {
    var on: Bool
    init(_ on: Bool) { self.on = on }
}
