import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct NeedsYouReasonTests {
    static let later = FakeWorld.epoch.addingTimeInterval(120)

    @MainActor
    final class Rig {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        var world = FakeWorld.realistic()

        func step() async throws -> Queue {
            let q = try await StoreDiffTests.queue(world)
            _ = store.diff(q, meuLogin: world.viewer)
            return q
        }

        func reason(_ key: String, in q: Queue) -> AppModel.NeedsReason? {
            AppModel.NeedsReason.of(
                key, unread: store.state.unread, reasons: store.state.unreadReasons,
                reviewRequested: q.toReview.contains { $0.key == key }
            )
        }
    }

    @Test func aFailingCheckIsNotShownAsAReply() async throws {
        let rig = Rig()
        _ = try await rig.step()
        rig.world.update("PR_0") { $0.checks = "FAILURE" }
        let q = try await rig.step()
        #expect(rig.store.state.unread.contains("acme/repo0#100"))
        #expect(rig.reason("acme/repo0#100", in: q) == .checkFailed)
        #expect(rig.reason("acme/repo0#100", in: q)?.label == "check failing")
    }

    @Test func eachEventKeepsItsOwnReason() async throws {
        let rig = Rig()
        _ = try await rig.step()
        rig.world.update("PR_1") {
            $0.threads[0].comments.append(FakeComment(author: "reviewer9", at: NeedsYouReasonTests.later, body: "@you is this safe?"))
        }
        rig.world.update("PR_20") {
            $0.conversation.append(FakeComment(author: "reviewer8", at: NeedsYouReasonTests.later, body: "looks fine"))
        }
        let q = try await rig.step()
        #expect(rig.reason("acme/repo1#101", in: q) == .replied)
        #expect(rig.reason("acme/repo0#120", in: q) == .commented)
        #expect(rig.reason("acme/repo2#114", in: q) == .reviewRequested)
    }

    @Test func aReplyOutranksAFailingCheckOnTheSamePullRequest() async throws {
        let rig = Rig()
        _ = try await rig.step()
        rig.world.update("PR_2") {
            $0.checks = "FAILURE"
            $0.threads[0].comments.append(FakeComment(author: "reviewer9", at: NeedsYouReasonTests.later, body: "@you why?"))
        }
        let q = try await rig.step()
        #expect(rig.reason("acme/repo2#102", in: q) == .replied)
    }

    @Test func aLaterCommentDoesNotHideAFailingCheck() async throws {
        let rig = Rig()
        _ = try await rig.step()
        rig.world.update("PR_3") { $0.checks = "FAILURE" }
        _ = try await rig.step()
        rig.world.update("PR_3") {
            $0.conversation.append(FakeComment(author: "reviewer8", at: NeedsYouReasonTests.later, body: "ping"))
        }
        let q = try await rig.step()
        #expect(rig.reason("acme/repo3#103", in: q) == .checkFailed)
    }

    @Test func aCheckThatPassesAgainLeavesNeedsYouByItself() async throws {
        let rig = Rig()
        _ = try await rig.step()
        rig.world.update("PR_0") { $0.checks = "FAILURE" }
        _ = try await rig.step()
        rig.world.update("PR_0") { $0.checks = "SUCCESS" }
        let q = try await rig.step()
        #expect(!rig.store.state.unread.contains("acme/repo0#100"))
        #expect(rig.reason("acme/repo0#100", in: q) == nil)
    }

    @Test func readingForgetsTheReason() async throws {
        let rig = Rig()
        _ = try await rig.step()
        rig.world.update("PR_0") { $0.checks = "FAILURE" }
        _ = try await rig.step()
        rig.store.markRead("acme/repo0#100")
        #expect(rig.store.state.unreadReasons["acme/repo0#100"] == nil)
        rig.store.markAllRead()
        #expect(rig.store.state.unreadReasons.isEmpty)
    }

    @Test func anUnreadKeyFromBeforeThisChangeStillReadsAsAReply() {
        let r = AppModel.NeedsReason.of("acme/repo0#100", unread: ["acme/repo0#100"], reasons: [:], reviewRequested: false)
        #expect(r == .replied)
    }

    @Test func anOlderStateWithoutReasonsStillDecodes() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(StoredState())) as! [String: Any]
        legacy.removeValue(forKey: "unreadReasons")
        legacy["unread"] = ["acme/repo0#100"]
        let decoded = try JSONDecoder().decode(StoredState.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.unread == ["acme/repo0#100"])
        #expect(decoded.unreadReasons.isEmpty)
    }

    @Test func aReviewAnswersTheRequestThatMadeItUnread() async throws {
        let rig = Rig()
        _ = try await rig.step()
        rig.world.toReview.append(FakeWorld.pr(41, author: "newcomer", viewer: rig.world.viewer))
        let q = try await rig.step()
        let key = try #require(q.toReview.first { $0.number == 141 }?.key)
        #expect(rig.store.state.unreadReasons[key] == .reviewRequested)
        rig.store.answeredReview(key)
        #expect(!rig.store.state.unread.contains(key))
    }

    @Test func aReviewLeavesAnUnreadAboutSomethingElse() async throws {
        let rig = Rig()
        _ = try await rig.step()
        rig.world.update("PR_0") { $0.checks = "FAILURE" }
        _ = try await rig.step()
        rig.store.answeredReview("acme/repo0#100")
        #expect(rig.store.state.unread.contains("acme/repo0#100"))
    }
}
