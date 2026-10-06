import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct ReviewTickTests {
    final class World: @unchecked Sendable {
        private let lock = NSLock()
        private var value: FakeWorld
        var reviewState: String? = "APPROVED"
        init(_ w: FakeWorld) { value = w }
        var world: FakeWorld {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    nonisolated static func reviewResponse(state: String?) -> Data {
        let review: [String: Any] = [
            "author": ["login": "you"],
            "submittedAt": ISO8601DateFormatter().string(from: Date()),
            "state": state ?? NSNull(),
        ]
        let data: [String: Any] = [
            "viewer": ["login": "you"],
            "repository": ["pullRequest": ["reviews": ["nodes": state == nil ? [] : [review]]]],
        ]
        return try! JSONSerialization.data(withJSONObject: ["data": data])
    }

    static func model(_ world: World) -> AppModel {
        let transport = StubTransport { body in
            if body.contains("MutationCheck") { return .init(body: Self.reviewResponse(state: world.reviewState)) }
            return .init(body: world.world.queueResponse())
        }
        return AppModel(
            client: GitHubClient(transport: transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
    }

    static func queue(_ world: FakeWorld) async throws -> Queue {
        let client = GitHubClient(transport: StubTransport(body: world.queueResponse()), tokens: CountingTokens(), metrics: Metrics())
        return try await client.fetchQueue()
    }

    @Test func githubReviewStatesReadAsVerdicts() {
        #expect(ReviewVerdict(github: "APPROVED") == .approved)
        #expect(ReviewVerdict(github: "CHANGES_REQUESTED") == .changesRequested)
        #expect(ReviewVerdict(github: "COMMENTED") == .commented)
        #expect(ReviewVerdict(github: nil) == .commented)
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

    @Test func theFirstSyncFindsNoCandidates() async throws {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        _ = store.diff(try await Self.queue(.realistic()), meuLogin: "you")
        #expect(store.unrequested.isEmpty)
    }

    @Test func aReviewIsCountedOnceAndTodayStartsOverTheNextDay() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        let at = Date()
        #expect(store.countReview("a", at: at, now: at) == 1)
        #expect(store.countReview("a", at: at, now: at) == nil)
        #expect(store.countReview("b", at: at, now: at) == 2)
        #expect(store.reviewsToday(now: at) == 2)
        let tomorrow = at.addingTimeInterval(86_400)
        #expect(store.reviewsToday(now: tomorrow) == 0)
        #expect(store.countReview("c", at: tomorrow, now: tomorrow) == 1)
    }

    @Test func todayGoesUpOnlyWhenTheSheetLands() {
        let t = ReviewTick(id: "t", pr: "acme/orders-api#7867", verdict: .approved, today: 4)
        #expect(ReviewStrip.today(t, at: 0.3) == 3)
        #expect(ReviewStrip.today(t, at: ReviewStrip.paperLands) == 4)
        #expect(ReviewStrip.today(t, at: 0, reducedMotion: true) == 4)
        #expect(ReviewStrip.shortPR("acme/orders-api#7867") == "orders-api#7867")
    }

    @Test func theBarFillsFromEmptyToFullAsTheSheetFallsIntoTheDrawer() {
        #expect(ReviewStrip.fill(at: 0) == 0)
        #expect(ReviewStrip.fill(at: ReviewStrip.paperLeaves) == 0)
        #expect(abs(ReviewStrip.fill(at: (ReviewStrip.paperLeaves + ReviewStrip.paperLands) / 2) - 0.5) < 1e-9)
        #expect(ReviewStrip.fill(at: ReviewStrip.paperLands) == 1)
        #expect(ReviewStrip.fill(at: ReviewStrip.length) == 1)
        #expect(ReviewStrip.fill(at: 0, reducedMotion: true) == 1)
        #expect(ReviewStrip.glow(at: ReviewStrip.paperLands) == 0)
        #expect(ReviewStrip.glow(at: ReviewStrip.paperLands + 0.175) > 0.99)
    }

    @Test func theBarStopsShortOfTheDrawer() {
        for width in [227.0, 269.0, 284.0] {
            let at = ReviewStrip.layout(wings: Wings(left: (width - 185) / 2, right: (width - 185) / 2),
                                        notchWidth: 185, notchHeight: 32)
            let drawerLeft = at.drawer.x - ReviewStrip.drawerSize.width / 2
            #expect(ReviewStrip.barSpan(width: CGFloat(width)).upperBound <= drawerLeft - 4)
        }
    }

    @Test func theDaysNumberSitsClearOfTheDrawer() {
        let at = ReviewStrip.layout(wings: Wings(left: 42, right: 42), notchWidth: 185, notchHeight: 32)
        let drawerRight = at.drawer.x + ReviewStrip.drawerSize.width / 2
        #expect(at.number.x - 8 >= drawerRight + 2)
        #expect(at.number.x + 8 <= 185 + 84)
    }

    @Test func theDrawerFillsUpWithTheDaysReviews() {
        #expect(ReviewStrip.sheets(for: 0) == 0)
        #expect(ReviewStrip.sheets(for: 1) == 1)
        #expect(ReviewStrip.sheets(for: 3) == 2)
        #expect(ReviewStrip.sheets(for: 7) == 3)
        #expect(ReviewStrip.sheets(for: 40) == 4)
        #expect((0...60).map(ReviewStrip.sheets(for:)) == (0...60).map(ReviewStrip.sheets(for:)).sorted())
    }

    @Test func theDrawerShakesWhenItShutsNotWhenTheSheetFalls() {
        let shut = ReviewStrip.drawerShuts + ReviewStrip.shutting
        #expect(ReviewStrip.opening(at: 0) == 0)
        #expect(ReviewStrip.opening(at: ReviewStrip.paperLands - 0.1) == 1)
        #expect(ReviewStrip.opening(at: ReviewStrip.paperLands + 0.1) == 1)
        #expect(ReviewStrip.opening(at: shut) == 0)
        for k in 0...Int((shut - ReviewStrip.paperLeaves) * 100) {
            #expect(ReviewStrip.shake(at: ReviewStrip.paperLeaves + Double(k) / 100) == 0)
        }
        #expect((1...30).contains { abs(ReviewStrip.shake(at: shut + Double($0) / 100)) > 0.5 })
        #expect(ReviewStrip.shake(at: shut + 0.4) == 0)
        #expect(shut + 0.35 < ReviewStrip.length - 0.2)
    }

    @Test func theSheetLeavesTheCountAndEndsInTheDrawer() {
        let from = CGPoint(x: 248, y: 16), to = CGPoint(x: 243, y: 42)
        #expect(ReviewStrip.flight(0, from: from, to: to, glide: 39).point == from)
        let end = ReviewStrip.flight(1, from: from, to: to, glide: 39).point
        #expect(abs(end.x - to.x) < 0.001 && abs(end.y - to.y) < 0.001)
        #expect(ReviewStrip.flight(0.5, from: from, to: to, glide: 39).point.y < (from.y + to.y) / 2)
    }

    @Test(arguments: [180.0, 185.0, 200.0, 210.0])
    func atEveryWidthTheSheetLeavesTheCountForTheDrawerAndStaysOutOfTheCutout(notch: Double) {
        let notchWidth = CGFloat(notch), notchHeight: CGFloat = 32, sheetHalf: CGFloat = 6.5
        var layouts: [(Wings, Bool)] = []
        for free in [60.0, 44, 38, 33, 29, 20] {
            for eye in [true, false] {
                for left in [false, true] {
                    layouts.append((NotchGeometry.wings(freeRight: free, full: 42, showsEye: eye, countOnLeft: left), eye))
                }
            }
        }
        for (wings, eye) in layouts {
            let width = wings.left + notchWidth + wings.right
            let at = ReviewStrip.layout(wings: wings, notchWidth: notchWidth, notchHeight: notchHeight, eyeBesideCount: eye)
            #expect(!at.cutout.contains(at.count.x), "count under the cutout: \(wings)")
            #expect(at.count.x > 0 && at.count.x < width)
            #expect(at.drawer.x > 0 && at.number.x < width)
            #expect(at.drawer.y - 5 >= notchHeight)
            let to = CGPoint(x: at.drawer.x, y: at.drawer.y + 1)
            #expect(ReviewStrip.flight(0, from: at.count, to: to, glide: at.rowY).point == at.count)
            let end = ReviewStrip.flight(1, from: at.count, to: to, glide: at.rowY).point
            #expect(abs(end.x - to.x) < 0.001 && abs(end.y - to.y) < 0.001)
            for k in 0...100 {
                let point = ReviewStrip.flight(Double(k) / 100, from: at.count, to: to, glide: at.rowY).point
                let inside = point.x > at.cutout.lowerBound + 5 && point.x < at.cutout.upperBound - 5
                if inside { #expect(point.y - sheetHalf >= notchHeight - 1.5, "sheet in the cutout: \(wings)") }
            }
        }
    }

    @Test func fromTheOtherSideTheSheetGoesUnderTheCutoutToFindTheDrawer() {
        let notchHeight: CGFloat = 32, cutout = 42.0...227.0, sheetHalf: CGFloat = 6.5
        let from = CGPoint(x: 21, y: 16), to = CGPoint(x: 201, y: 42)
        for i in 0...100 {
            let point = ReviewStrip.flight(Double(i) / 100, from: from, to: to, glide: 40).point
            if cutout.contains(Double(point.x)) { #expect(point.y - sheetHalf >= notchHeight - 1.5) }
        }
        let end = ReviewStrip.flight(1, from: from, to: to, glide: 40).point
        #expect(abs(end.x - to.x) < 0.001 && abs(end.y - to.y) < 0.001)
    }

    final class Gate {
        var waiting: [CheckedContinuation<Void, Never>] = []
        func open() { let w = waiting; waiting = []; w.forEach { $0.resume() } }
    }

    final class Flag { var on: Bool; init(_ on: Bool) { self.on = on } }

    func notch(full: Flag = Flag(false), gate: Gate) -> NotchController {
        let n = NotchController()
        n.wakes = false
        n.fullScreen = { full.on }
        n.pointer = { CGPoint(x: -1000, y: -1000) }
        n.nap = { _ in await withCheckedContinuation { gate.waiting.append($0) } }
        n.settleBeforeFirstFrame()
        return n
    }

    func step(_ gate: Gate) async {
        while gate.waiting.isEmpty { await Task.yield() }
        gate.open()
        await Task.yield()
    }

    func drain(_ gate: Gate, _ n: NotchController) async {
        while n.tick != nil || !n.pendingTicks.isEmpty {
            if gate.waiting.isEmpty { await Task.yield() } else { gate.open() }
        }
    }

    static func tick(_ pr: String, today: Int = 3) -> ReviewTick {
        ReviewTick(id: pr, pr: pr, verdict: .approved, today: today)
    }

    @Test func aReviewOpensAThinStripUnderTheNotchAndClosesIt() async {
        let gate = Gate()
        let n = notch(gate: gate)
        n.tick(Self.tick("a"))
        let resting = NotchGeometry.current().active(n.wings)
        #expect(n.tick?.pr == "a")
        #expect(n.size == CGSize(width: resting.width, height: resting.height + ReviewStrip.drawer))
        await drain(gate, n)
        #expect(n.size == resting)
    }

    @Test func theCountHoldsUntilTheSheetLeavesItThenLetsGo() async {
        let gate = Gate()
        let n = notch(gate: gate)
        n.expectReviews(["a"], showing: 8)
        #expect(n.heldCount == 8)
        n.tick(Self.tick("a"))
        #expect(n.heldCount == 8)
        await step(gate)
        #expect(n.heldCount == 7)
        await drain(gate, n)
        #expect(n.heldCount == nil)
    }

    @Test func aCandidateThatWasNotAReviewLetsTheCountGo() {
        let n = notch(gate: Gate())
        n.expectReviews(["a", "b"], showing: 8)
        n.noReview("a")
        #expect(n.heldCount == 8)
        n.noReview("b")
        #expect(n.heldCount == nil)
    }

    @Test func aHoldNobodyAnswersLetsGoOnItsOwn() async {
        let n = notch(gate: Gate())
        n.holdsAtMost = .milliseconds(20)
        n.expectReviews(["a"], showing: 8)
        for _ in 0..<200 where n.heldCount != nil { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(n.heldCount == nil)
    }

    @Test func overAFullScreenAppTheStripWaitsForTheNotchToComeBack() {
        let full = Flag(true)
        let n = notch(full: full, gate: Gate())
        n.tick(Self.tick("a"))
        #expect(n.state == .hidden)
        #expect(n.tick == nil)
        full.on = false
        n.refreshIdle()
        #expect(n.tick?.pr == "a")
    }

    @Test func aReviewFoundBySyncHoldsTheCountAndTicksToday() async throws {
        var start = FakeWorld.realistic()
        start.toReview.append(FakeWorld.pr(40, author: "newcomer", viewer: "you"))
        let world = World(start)
        let model = Self.model(world)
        var held: [([String], Int)] = []
        var ticks: [ReviewTick] = []
        model.onReviewsPending = { held.append(($0, $1)) }
        model.onTick = { ticks.append($0) }
        await model.refresh(full: true)
        await model.refresh(full: true)
        let before = model.count
        world.world.toReview.removeLast()
        await model.refresh(full: true)
        #expect(held.count == 1)
        #expect(held.first?.1 == before)
        for _ in 0..<300 where ticks.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(ticks.map(\.today) == [1])
        #expect(ticks.first?.verdict == .approved)
    }

    @Test func aRequestDroppedWithoutAReviewTicksNothing() async throws {
        var start = FakeWorld.realistic()
        start.toReview.append(FakeWorld.pr(40, author: "newcomer", viewer: "you"))
        let world = World(start)
        world.reviewState = nil
        let model = Self.model(world)
        var released: [String] = []
        var ticks: [ReviewTick] = []
        model.onNoReview = { released.append($0) }
        model.onTick = { ticks.append($0) }
        await model.refresh(full: true)
        await model.refresh(full: true)
        world.world.toReview.removeLast()
        await model.refresh(full: true)
        for _ in 0..<300 where released.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(released.count == 1)
        #expect(ticks.isEmpty)
    }

    @Test func aReviewOfAPROpenedFromDipleLeavesNeedsYouAtOnce() async throws {
        let world = World(.realistic())
        let model = Self.model(world)
        await model.refresh(full: true)
        let pr = try #require(model.reviewing.first)
        let before = model.count
        var held: [([String], Int)] = []
        var ticks: [ReviewTick] = []
        model.onReviewsPending = { held.append(($0, $1)) }
        model.onTick = { ticks.append($0) }
        model.reviewedFromDiple(pr.key, at: Date(), verdict: .changesRequested)
        #expect(held.first?.0 == [pr.key])
        #expect(held.first?.1 == before)
        #expect(!model.reviewing.contains { $0.key == pr.key })
        #expect(model.count == before - 1)
        #expect(ticks.map(\.verdict) == [.changesRequested])

        world.world.toReview.removeAll { "\($0.repo)#\($0.number)" == pr.key || $0.id == pr.id }
        await model.refresh(full: true)
        #expect(ticks.count == 1)
        #expect(!model.queue.toReview.contains { $0.key == pr.key })
        #expect(model.reviewedAhead.isEmpty)
    }

    @Test func aReviewOfARequestThatArrivedWhileOpenLeavesTheCountAtOnce() async throws {
        let world = World(.realistic())
        let model = Self.model(world)
        model.settings.alerts[EventKind.reviewRequested.rawValue] = false
        await model.refresh(full: true)
        world.world.toReview.append(FakeWorld.pr(41, author: "newcomer", viewer: "you"))
        await model.refresh(full: true)
        let pr = try #require(model.reviewing.first { $0.number == 141 })
        #expect(model.unread.contains(pr.key))
        let before = model.count

        model.reviewedFromDiple(pr.key, at: Date(), verdict: .approved)
        #expect(model.count == before - 1)
        #expect(!model.unread.contains(pr.key))
    }

    @Test func turningItOffTicksNothingFromSync() async throws {
        var start = FakeWorld.realistic()
        start.toReview.append(FakeWorld.pr(40, author: "newcomer", viewer: "you"))
        let world = World(start)
        let model = Self.model(world)
        model.settings.showsReviews = false
        var held = 0
        model.onReviewsPending = { _, _ in held += 1 }
        await model.refresh(full: true)
        await model.refresh(full: true)
        world.world.toReview.removeLast()
        await model.refresh(full: true)
        #expect(held == 0)
    }
}
