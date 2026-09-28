import Foundation
import Testing
@testable import Diple

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = FakeWorld.epoch
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@Suite struct SyncEngineTests {
    struct Rig {
        let github: FakeGitHub
        let metrics = Metrics()
        let clock = FakeClock()
        let engine: SyncEngine
        let reference: GitHubClient

        init(_ world: FakeWorld = .realistic()) {
            github = FakeGitHub(world)
            let client = GitHubClient(
                transport: github.transport, tokens: CountingTokens(), metrics: metrics, retryDelays: [.zero, .zero]
            )
            let clock = self.clock
            engine = SyncEngine(client: client, now: { clock.now })
            reference = GitHubClient(
                transport: StubTransport { [github] _ in .init(body: github.world.queueResponse()) },
                tokens: CountingTokens(), metrics: Metrics()
            )
        }

        func cycle() async throws -> (queue: Queue, kinds: [String], bytes: Int) {
            let before = github.transport.queries.count
            let bytesBefore = metrics.snapshot().count(.bytesIn)
            let q = try await engine.sync().queue
            let raw = github.transport.queries.dropFirst(before).map(FakeGitHub.kind)
            let kinds = raw.reduce(into: [String]()) { out, k in if out.last != k { out.append(k) } }
            return (q, kinds, metrics.snapshot().count(.bytesIn) - bytesBefore)
        }

        func truth() async throws -> Queue { try await reference.fetchQueue() }
    }

    static let later = FakeWorld.epoch.addingTimeInterval(60)

    @Test func theFirstSyncIsFull() async throws {
        let rig = Rig()
        let c = try await rig.cycle()
        #expect(c.kinds == ["full"])
        let truth = try await rig.truth()
        #expect(c.queue == truth)
    }

    @Test func aSteadyCycleIsOneSmallRequest() async throws {
        let rig = Rig()
        _ = try await rig.cycle()
        let before = rig.github.transport.queries.count
        let c = try await rig.cycle()
        #expect(c.kinds == ["beat"])
        #expect(rig.github.transport.queries.count - before == 3)
        #expect(c.bytes < 8_000)
        let truth = try await rig.truth()
        #expect(c.queue == truth)
    }

    @Test func onlyTheChangedPullRequestIsFetchedInFull() async throws {
        let rig = Rig()
        _ = try await rig.cycle()
        rig.github.edit { w in
            w.update("PR_3") {
                $0.title = "Renamed"
                $0.updatedAt = Self.later
            }
        }
        let c = try await rig.cycle()
        #expect(c.kinds == ["beat", "detail"])
        #expect(FakeGitHub.ids(in: rig.github.transport.queries.last ?? "") == ["PR_3"])
        #expect(c.queue.mine.first { $0.id == "PR_3" }?.title == "Renamed")
        let truth = try await rig.truth()
        #expect(c.queue == truth)
    }

    @Test func aCheckThatFinishesWithoutTouchingUpdatedAtIsSeen() async throws {
        let rig = Rig()
        _ = try await rig.cycle()
        rig.github.edit { w in w.update("PR_0") { $0.checks = "FAILURE" } }
        let c = try await rig.cycle()
        #expect(c.kinds == ["beat", "detail"])
        #expect(c.queue.mine.first { $0.id == "PR_0" }?.checks == .failing)
    }

    @Test func movingBetweenSectionsNeedsNoDetails() async throws {
        let rig = Rig()
        _ = try await rig.cycle()
        rig.github.edit { w in
            let moved = w.following.removeFirst()
            w.toReview.insert(moved, at: 0)
        }
        let c = try await rig.cycle()
        #expect(c.kinds == ["beat"])
        let truth = try await rig.truth()
        #expect(c.queue == truth)
    }

    @Test func aNewPullRequestIsFetchedAndAGoneOneDisappears() async throws {
        let rig = Rig()
        _ = try await rig.cycle()
        rig.github.edit { w in
            w.following.removeLast()
            w.toReview.append(FakeWorld.pr(77, author: "newcomer", viewer: "you"))
        }
        let c = try await rig.cycle()
        #expect(c.kinds == ["beat", "detail"])
        #expect(FakeGitHub.ids(in: rig.github.transport.queries.last ?? "") == ["PR_77"])
        let truth = try await rig.truth()
        #expect(c.queue == truth)
    }

    @Test func aDetailThatDoesNotComeBackFallsBackToFull() async throws {
        let rig = Rig()
        _ = try await rig.cycle()
        rig.github.edit { w in w.update("PR_5") { $0.updatedAt = Self.later } }
        rig.github.hideFromDetails(["PR_5"])
        let c = try await rig.cycle()
        #expect(c.kinds == ["beat", "detail", "full"])
        let truth = try await rig.truth()
        #expect(c.queue == truth)
    }

    @Test func itReconcilesWithAFullFetchEveryHalfHour() async throws {
        let rig = Rig()
        _ = try await rig.cycle()
        rig.clock.advance(29 * 60)
        let kinds7 = try await rig.cycle().kinds
        #expect(kinds7 == ["beat"])
        rig.clock.advance(2 * 60)
        let kinds8 = try await rig.cycle().kinds
        #expect(kinds8 == ["full"])
        let kinds9 = try await rig.cycle().kinds
        #expect(kinds9 == ["beat"])
    }

    @Test func aForcedSyncIsFull() async throws {
        let rig = Rig()
        _ = try await rig.cycle()
        _ = try await rig.engine.sync(full: true)
        #expect(FakeGitHub.kind(rig.github.transport.queries.last ?? "") == "full")
    }

    @Test func aSeededEngineStartsWithAHeartbeat() async throws {
        let rig = Rig()
        await rig.engine.seed(try await rig.truth())
        let c = try await rig.cycle()
        #expect(c.kinds == ["beat"])
        let truth = try await rig.truth()
        #expect(c.queue == truth)
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func incrementalAlwaysEqualsAFullFetch(seed: Int) async throws {
        let rig = Rig()
        _ = try await rig.cycle()
        var rng = SeededGenerator(seed: UInt64(seed))
        var clock = FakeWorld.epoch
        var created = 100
        for _ in 0..<40 {
            clock = clock.addingTimeInterval(30)
            let at = clock
            let roll = Int.random(in: 0..<8, using: &rng)
            let pick = Int.random(in: 0..<1000, using: &rng)
            rig.github.edit { w in
                let ids = w.all.map(\.id)
                guard !ids.isEmpty else { return }
                let id = ids[pick % ids.count]
                switch roll {
                case 0: w.update(id) { $0.title += "!"; $0.updatedAt = at }
                case 1: w.update(id) {
                    $0.threads[0].comments.append(FakeComment(author: "reviewer7", at: at, body: "again?"))
                    $0.updatedAt = at
                }
                case 2: w.update(id) { $0.checks = $0.checks == "SUCCESS" ? "PENDING" : "SUCCESS" }
                case 3: w.update(id) { $0.decision = "APPROVED"; $0.updatedAt = at }
                case 4: w.update(id) { $0.draft.toggle(); $0.updatedAt = at }
                case 5:
                    if !w.following.isEmpty { w.toReview.append(w.following.removeFirst()) }
                case 6:
                    created += 1
                    w.following.insert(FakeWorld.pr(created, author: "teammate\(created)", viewer: "you"), at: 0)
                default:
                    if !w.mine.isEmpty { w.mine.remove(at: pick % w.mine.count) }
                }
            }
            let c = try await rig.cycle()
            let truth = try await rig.truth()
            #expect(c.queue == truth)
            #expect(!c.kinds.contains("full"))
        }
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
