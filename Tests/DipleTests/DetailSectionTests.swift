import Foundation
import Testing
@testable import Diple

@MainActor
struct DetailSectionTests {
    @Test func eachPullRequestReopensOnTheTabItWasLeftOn() {
        let model = AppModel(store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics()))
        #expect(model.section(for: "o/r#1") == .conversation)

        model.remember(.map, for: "o/r#1")
        model.remember(.ai, for: "o/r#2")

        #expect(model.section(for: "o/r#1") == .map)
        #expect(model.section(for: "o/r#2") == .ai)
        #expect(model.section(for: "o/r#3") == .conversation)
    }
}

@Suite struct AIReviewTabTests {
    static func prs() async throws -> (mine: PR, theirs: PR) {
        let q = try await StoreDiffTests.queue(.realistic())
        return (q.mine[0], q.toReview[0])
    }

    @Test func yourOwnPullRequestHasTheAIReviewTab() async throws {
        let (mine, _) = try await Self.prs()
        #expect(DetailView.Section.available(for: mine) == [.conversation, .map, .ai])
    }

    @Test func someoneElsesPullRequestHasNoAIReviewTab() async throws {
        let (_, theirs) = try await Self.prs()
        #expect(DetailView.Section.available(for: theirs) == [.conversation, .map])
    }

    @Test func aRememberedAIReviewTabFallsBackToConversationOnSomeoneElsesPR() async throws {
        let (mine, theirs) = try await Self.prs()
        #expect(DetailView.Section.shown(.ai, for: theirs) == .conversation)
        #expect(DetailView.Section.shown(.map, for: theirs) == .map)
        #expect(DetailView.Section.shown(.ai, for: mine) == .ai)
    }
}
