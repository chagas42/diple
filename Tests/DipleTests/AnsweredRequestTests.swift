import Foundation
import Testing
@testable import Diple

@Suite struct AnsweredRequestTests {
    static let asked = FakeWorld.epoch.addingTimeInterval(-3600)
    static let before = asked.addingTimeInterval(-60)
    static let after = asked.addingTimeInterval(60)
    static let later = asked.addingTimeInterval(600)

    static func request(_ change: (inout FakePR) -> Void) async throws -> PR {
        var w = FakeWorld()
        var pr = FakeWorld.pr(14, author: "teammate", viewer: w.viewer)
        pr.requests = [FakeRequest(reviewer: w.viewer, at: asked)]
        change(&pr)
        w.toReview = [pr]
        return try #require(try await StoreDiffTests.queue(w).toReview.first)
    }

    @Test func aRequestNobodyAnsweredStillNeedsYou() async throws {
        #expect(try await !Self.request { _ in }.answeredByViewer)
    }

    @Test func aCommentOfYoursAfterTheRequestAnswersIt() async throws {
        let pr = try await Self.request { $0.conversation.append(FakeComment(author: "you", at: Self.after, body: "lgtm, one nit")) }
        #expect(pr.answeredByViewer)
    }

    @Test func aReplyOfYoursOnALineAnswersIt() async throws {
        let pr = try await Self.request { $0.threads[0].comments.append(FakeComment(author: "you", at: Self.after, body: "fixed?")) }
        #expect(pr.answeredByViewer)
    }

    @Test func aReviewOfYoursAfterTheRequestAnswersIt() async throws {
        let pr = try await Self.request { $0.reviews = [FakeReview(author: "you", state: "COMMENTED", at: Self.after)] }
        #expect(pr.answeredByViewer)
    }

    @Test func aCommentFromBeforeTheRequestDoesNot() async throws {
        let pr = try await Self.request { $0.conversation.append(FakeComment(author: "you", at: Self.before, body: "early look")) }
        #expect(!pr.answeredByViewer)
    }

    @Test func aRequestAgainAfterYourCommentBringsItBack() async throws {
        let pr = try await Self.request {
            $0.conversation.append(FakeComment(author: "you", at: Self.after, body: "please split it"))
            $0.requests.append(FakeRequest(reviewer: "you", at: Self.later))
        }
        #expect(!pr.answeredByViewer)
    }

    @Test func aRequestToATeamCountsAsAskingYou() async throws {
        let pr = try await Self.request {
            $0.requests = [FakeRequest(reviewer: "", team: true, at: Self.later)]
            $0.conversation.append(FakeComment(author: "you", at: Self.after, body: "seen"))
        }
        #expect(!pr.answeredByViewer)
    }

    @Test func aRequestToSomeoneElseDoesNotBringItBack() async throws {
        let pr = try await Self.request {
            $0.conversation.append(FakeComment(author: "you", at: Self.after, body: "done"))
            $0.requests.append(FakeRequest(reviewer: "bea", at: Self.later))
        }
        #expect(pr.answeredByViewer)
    }

    @Test func aCommitAfterYourCommentBringsItBack() async throws {
        let pr = try await Self.request {
            $0.conversation.append(FakeComment(author: "you", at: Self.after, body: "needs a test"))
            $0.committedAt = Self.later
        }
        #expect(!pr.answeredByViewer)
    }

    @Test func aPendingReviewOfYoursHasNotAnsweredYet() async throws {
        let pr = try await Self.request {
            $0.threads[0].comments.append(FakeComment(author: "you", at: Self.after, body: "draft", pending: true))
            $0.reviews = [FakeReview(author: "you", state: "PENDING", at: nil)]
        }
        #expect(!pr.answeredByViewer)
    }

    @Test func withoutTheRequestTimeNothingIsHidden() async throws {
        let pr = try await Self.request {
            $0.requests = []
            $0.conversation.append(FakeComment(author: "you", at: Self.after, body: "seen"))
        }
        #expect(!pr.answeredByViewer)
    }

    @Test func aPullRequestCachedBeforeTheseFieldsDecodesAsUnanswered() throws {
        let pr = ReviewFilterTests.pr(1, by: "bea")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pr)) as! [String: Any]
        json.removeValue(forKey: "askedAt")
        json.removeValue(forKey: "viewerActedAt")
        let decoded = try JSONDecoder().decode(PR.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!decoded.answeredByViewer)
    }

    @Test func mergedOrClosedPullRequestsAreNotSearchedForAtAll() {
        for (section, search) in Query.searches(watching: ["o/r"]) {
            #expect(search.hasPrefix("is:open "), "\(section)")
        }
    }

    @MainActor
    @Test func anAnsweredRequestLeavesNeedsYouAndTheCountButStaysInReviewing() async throws {
        var w = FakeWorld.realistic()
        w.update("PR_14") {
            $0.requests = [FakeRequest(reviewer: "you", at: Self.asked)]
            $0.conversation.append(FakeComment(author: "you", at: Self.after, body: "lgtm"))
        }
        let model = LaunchCacheTests.model(StoreDiffTests.tempDirectory(), StubTransport(body: w.queueResponse()))
        model.preloadsTabs = false
        await model.refresh()
        #expect(model.prs(.reviewing).contains { $0.key == "acme/repo2#114" })
        #expect(!model.needsYou.contains { $0.key == "acme/repo2#114" })
        #expect(model.count == model.needsYou.count)
        #expect(model.needsYou.contains { $0.key == "acme/repo3#115" })
    }
}
