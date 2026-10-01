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

    @Test func theTrailFillsEvenlyBetweenMilestones() {
        #expect(CollectionView.trailFill(0) == 0)
        #expect(abs(CollectionView.trailFill(10) - 1.0 / 6) < 0.001)
        #expect(abs(CollectionView.trailFill(20) - 1.5 / 6) < 0.001)
        #expect(CollectionView.trailFill(300) == 1)
    }

    @Test func aStickerAlwaysLandsInTheSameSpotAndLeavesTheLogoClear() {
        for i in 0..<200 {
            let p = LidView.placement(for: "sticker-\(i)")
            #expect(p == LidView.placement(for: "sticker-\(i)"))
            #expect(!(abs(p.x - 0.5) < 0.14 && abs(p.y - 0.5) < 0.18))
            #expect(p.x > 0 && p.x < 1 && p.y > 0 && p.y < 1)
            #expect(LidView.clamped(LidSpot(x: 2, y: -1, angle: 0, size: 0.1)) == LidSpot(x: 0.95, y: 0.07, angle: 0, size: 0.1))
        }
    }

    @Test func theSeasonCountsUpAndStartsOverWithANewQuarter() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        #expect(store.advanceSeason("2026-Q3") == 1)
        #expect(store.advanceSeason("2026-Q3") == 2)
        #expect(store.advanceSeason("2026-Q4") == 1)
    }

    @Test func onlyAReviewOnAMilestoneEarnsASticker() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        let model = AppModel(
            client: GitHubClient(transport: StubTransport(body: Data()), tokens: CountingTokens(), metrics: Metrics()),
            store: store
        )
        model.settings.rewardsBeta = true
        let now = Date()
        store.setSeason(SeasonProgress(id: Trail.season(of: now), reviews: 8))
        var earned: [Reward] = []
        model.onReward = { earned.append($0) }
        model.counted(pr: "acme/a#1", at: now, verdict: .commented)
        #expect(earned.isEmpty)
        model.counted(pr: "acme/a#2", at: now.addingTimeInterval(1), verdict: .approved)
        #expect(earned.map(\.artifact.rarity) == [.common])
        #expect(model.seasonReviews == 10)
    }

    @Test func withRewardsOffTheTrailDoesNotMove() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        let model = AppModel(
            client: GitHubClient(transport: StubTransport(body: Data()), tokens: CountingTokens(), metrics: Metrics()),
            store: store
        )
        var earned = 0
        model.onReward = { _ in earned += 1 }
        for i in 0..<12 { model.counted(pr: "acme/a#\(i)", at: Date().addingTimeInterval(Double(i)), verdict: .approved) }
        #expect(earned == 0)
        #expect(store.state.season == nil)
    }

    @Test func whereAStickerIsStuckIsKept() {
        let dir = StoreDiffTests.tempDirectory()
        let spot = LidSpot(x: 0.3, y: 0.4, angle: -8, size: 0.15)
        let store = Store(directory: dir, metrics: Metrics())
        store.stick("x", at: spot)
        store.flushNow()
        #expect(Store(directory: dir, metrics: Metrics()).state.lidSpots["x"] == spot)
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
        let n = notch(gate: Gate())
        n.reward(Reward(id: "t", artifact: .sample(.common), pr: "acme/orders-api#7867"))
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
