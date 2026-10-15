import Foundation
import Testing
@testable import Diple

@Suite struct MuteTests {
    static let then = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 86_400

    @Test func aMuteOnAPullRequestStillInTheQueueIsKeptAndRefreshedDaily() {
        var q = Queue()
        q.toReview = [DismissalTests.pr(1, updatedAt: Self.then)]
        let muted = ["o/r#1": Self.then]
        #expect(Mutes.kept(muted, queue: q, now: Self.then.addingTimeInterval(3600)) == muted)
        let later = Self.then.addingTimeInterval(90 * Self.day)
        #expect(Mutes.kept(muted, queue: q, now: later) == ["o/r#1": later])
    }

    @Test func aMuteSurvivesUpdatesToItsPullRequest() {
        var q = Queue()
        q.toReview = [DismissalTests.pr(1, updatedAt: Self.then.addingTimeInterval(600))]
        #expect(Mutes.kept(["o/r#1": Self.then], queue: q, now: Self.then) == ["o/r#1": Self.then])
    }

    @Test func aPullRequestOutOfTheQueueStaysMutedForAMonth() {
        let muted = ["o/r#9": Self.then]
        #expect(Mutes.kept(muted, queue: Queue(), now: Self.then.addingTimeInterval(29 * Self.day)) == muted)
        #expect(Mutes.kept(muted, queue: Queue(), now: Self.then.addingTimeInterval(31 * Self.day)).isEmpty)
    }

    @Test func anOlderStateWithoutMutesStillDecodes() throws {
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(StoredState())) as! [String: Any]
        legacy.removeValue(forKey: "muted")
        let decoded = try JSONDecoder().decode(StoredState.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.muted == nil)
    }

    @MainActor
    @Test func mutingHidesFromTheNotchButNotTheWindowAndSurvivesARelaunch() async throws {
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
        let tab = try #require(AppModel.Tab.allCases.first { $0 != .needsYou && model.prs($0).contains { $0.key == first.key } })
        let before = model.count

        model.mute(first)
        #expect(model.count == before - 1)
        #expect(!model.needsYou.contains { $0.key == first.key })
        #expect(!model.prs(tab).contains { $0.key == first.key })
        #expect(model.prs(tab, includingMuted: true).contains { $0.key == first.key })
        await model.settleState()
        #expect(Store(directory: directory, metrics: Metrics()).state.muted?[first.key] != nil)

        model.unmute(first)
        #expect(model.prs(tab).contains { $0.key == first.key })
        await model.settleState()
        #expect(Store(directory: directory, metrics: Metrics()).state.muted?[first.key] == nil)
    }
}
