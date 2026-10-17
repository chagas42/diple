import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct TrackingTests {
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    static func pr(
        at minutes: Double = 0, head: String = "aaa", checks: CheckState = .running,
        approvals: Int = 0, changes: Int = 0, comment: PR.HumanComment? = nil, state: PRState = .open
    ) -> PR {
        var p = PR(
            id: "PR_node", repo: "acme/api", number: 7, title: "Retry on 429",
            url: URL(string: "https://github.com/acme/api/pull/7")!,
            updatedAt: epoch.addingTimeInterval(minutes * 60), createdAt: epoch, draft: false,
            author: "teammate", authorAvatar: nil, isMine: false,
            headRef: "fix", baseRef: "main", checks: checks, approved: approvals > 0,
            threads: [], lastComment: comment, head: head,
            approvals: approvals, changesRequested: changes
        )
        p.state = state
        return p
    }

    static func comment(_ text: String, at minutes: Double) -> PR.HumanComment {
        .init(author: "reviewer", at: epoch.addingTimeInterval(minutes * 60), excerpt: text,
              location: nil, threadId: nil)
    }

    static func titles(_ before: PR, _ after: PR) -> [String] {
        Tracking.events(TrackedPR(before), now: after, viewer: "you").map(\.title)
    }

    @Test func unchangedPRSaysNothing() {
        #expect(Self.titles(Self.pr(), Self.pr()).isEmpty)
    }

    @Test func eachChangeRaisesItsEvent() {
        let after = Self.pr(at: 5, head: "bbb", checks: .failing, approvals: 1, changes: 1,
                            comment: Self.comment("looks good", at: 5))
        #expect(Self.titles(Self.pr(), after) == [
            "New commits on a PR you track",
            "reviewer commented on a PR you track",
            "A PR you track was approved",
            "Changes requested on a PR you track",
            "A check failed on a PR you track",
        ])
    }

    @Test func mentionBecomesAReply() {
        let events = Tracking.events(TrackedPR(Self.pr()), now: Self.pr(at: 1, comment: Self.comment("@you thoughts?", at: 1)), viewer: "you")
        #expect(events.map(\.kind) == [.repliedToYou])
    }

    @Test func checksRecoveringIsNews() {
        #expect(Self.titles(Self.pr(checks: .failing), Self.pr(checks: .passing)) == ["Checks passed on a PR you track"])
        #expect(Self.titles(Self.pr(checks: .none), Self.pr(checks: .passing)).isEmpty)
    }

    @Test func mergeIsTheOnlyEventItRaises() {
        let after = Self.pr(at: 9, head: "ccc", approvals: 2, state: .merged)
        #expect(Self.titles(Self.pr(), after) == ["A PR you track was merged"])
    }

    @Test func beatMovesOnlyWhenSomethingTrackedChanged() {
        let mark = TrackMark(Self.pr())
        let same = TrackBeat(id: "PR_node", updatedAt: Self.epoch, state: .open, head: "aaa", checks: .running)
        #expect(!mark.moved(same))
        #expect(mark.moved(TrackBeat(id: "PR_node", updatedAt: Self.epoch, state: .open, head: "aaa", checks: .passing)))
        #expect(mark.moved(TrackBeat(id: "PR_node", updatedAt: Self.epoch, state: .merged, head: "aaa", checks: .running)))
    }

    @Test func parsesLinksAndShortKeys() {
        #expect(Tracking.parse("https://github.com/acme/api/pull/7")! == ("acme/api", 7))
        #expect(Tracking.parse(" https://github.com/acme/api/pull/7/files ")! == ("acme/api", 7))
        #expect(Tracking.parse("acme/api#7")! == ("acme/api", 7))
        #expect(Tracking.parse("https://github.com/acme/api/issues/7") == nil)
        #expect(Tracking.parse("hello") == nil)
    }

    @Test func storeKeepsTrackingUntilMerge() {
        let store = Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        store.track(Self.pr())

        let pushed = Self.pr(at: 1, head: "bbb")
        #expect(store.absorbTracked([pushed], viewer: "you").count == 1)
        #expect(store.absorbTracked([pushed], viewer: "you").isEmpty)
        #expect(store.state.unread.contains("acme/api#7"))

        #expect(store.absorbTracked([Self.pr(at: 2, head: "bbb", state: .merged)], viewer: "you").count == 1)
        #expect(store.state.tracked?["acme/api#7"] == nil)
    }

    @Test func oldStateFilesStillLoad() throws {
        let old = #"{"version":1,"prs":{},"unread":[],"hasRunBefore":true}"#
        let state = try JSONDecoder().decode(StoredState.self, from: Data(old.utf8))
        #expect(state.tracked == nil)
        #expect(state.hasRunBefore)
    }

    @Test func queueEventsTheTrackerOwnsAreDropped() {
        #expect(Tracking.handled(.commented))
        #expect(Tracking.handled(.checkFailed))
        #expect(!Tracking.handled(.reviewRequested))
    }
}
