import Foundation
import Testing
@testable import Diple

@Suite struct DismissalTests {
    static let then = Date(timeIntervalSince1970: 1_800_000_000)

    static func pr(_ n: Int, updatedAt: Date) -> PR {
        PR(id: "\(n)", repo: "o/r", number: n, title: "t\(n)",
           url: URL(string: "https://github.com/o/r/pull/\(n)")!,
           updatedAt: updatedAt, createdAt: updatedAt, draft: false,
           author: "bea", authorAvatar: nil, isMine: false,
           headRef: "h", baseRef: "main", checks: .none, approved: false,
           threads: [], lastComment: nil)
    }

    @Test func aDismissedPullRequestStaysHiddenUntilItIsUpdatedAgain() {
        let dismissed = ["o/r#1": Self.then]
        #expect(Dismissals.hides(Self.pr(1, updatedAt: Self.then), dismissed))
        #expect(!Dismissals.hides(Self.pr(1, updatedAt: Self.then.addingTimeInterval(1)), dismissed))
        #expect(!Dismissals.hides(Self.pr(2, updatedAt: Self.then), dismissed))
    }

    @Test func aDismissalIsForgottenOnceItsPullRequestMovesOn() {
        var q = Queue()
        q.toReview = [Self.pr(1, updatedAt: Self.then.addingTimeInterval(60)), Self.pr(2, updatedAt: Self.then)]
        let kept = Dismissals.kept(["o/r#1": Self.then, "o/r#2": Self.then], queue: q, now: Self.then)
        #expect(kept == ["o/r#2": Self.then])
    }

    @Test func aPullRequestOutOfTheQueueIsRememberedForAMonth() {
        let dismissed = ["o/r#9": Self.then]
        #expect(Dismissals.kept(dismissed, queue: Queue(), now: Self.then.addingTimeInterval(29 * 86_400)) == dismissed)
        #expect(Dismissals.kept(dismissed, queue: Queue(), now: Self.then.addingTimeInterval(31 * 86_400)).isEmpty)
    }

    @Test func anOlderStateWithoutDismissalsStillDecodes() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(StoredState())) as! [String: Any]
        legacy.removeValue(forKey: "dismissed")
        legacy["unread"] = ["o/r#1"]
        let decoded = try JSONDecoder().decode(StoredState.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.unread == ["o/r#1"])
        #expect(decoded.dismissed == nil)
    }

    @MainActor
    @Test func dismissingLeavesTheCountAndSurvivesARelaunch() async throws {
        let gh = ReviewGitHub()
        let directory = StoreDiffTests.tempDirectory()
        let model = AppModel(
            client: GitHubClient(transport: gh.transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: directory, metrics: Metrics()),
            fetchRefs: gh.fetchRefs
        )
        model.preloadsTabs = false
        await model.refresh()
        let first = try #require(model.needsYou.first)
        let before = model.count
        model.dismiss(first)
        #expect(model.count == before - 1)
        #expect(!model.needsYou.contains { $0.key == first.key })
        await model.settleState()

        let reopened = Store(directory: directory, metrics: Metrics())
        #expect(reopened.state.dismissed?[first.key] == first.updatedAt)
    }
}
