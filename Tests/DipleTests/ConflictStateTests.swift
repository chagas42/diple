import Foundation
import Testing
@testable import Diple

@Suite struct ConflictStateTests {
    @Test func gitHubsAnswerIsRead() {
        #expect(Mergeable(github: "CONFLICTING") == .conflicting)
        #expect(Mergeable(github: "MERGEABLE") == .mergeable)
        #expect(Mergeable(github: "UNKNOWN") == .unknown)
        #expect(Mergeable(github: "SOMETHING_NEW") == .unknown)
    }

    static let at = Date(timeIntervalSince1970: 1_790_000_000)

    static func beat(_ m: Mergeable?) -> Beat {
        Beat(updatedAt: at, draft: false, checks: .passing, approved: false, mergeable: m)
    }

    @Test func aBranchThatStartsConflictingIsReadAgain() {
        #expect(!Self.beat(.mergeable).matches(Self.beat(.conflicting)))
        #expect(!Self.beat(.conflicting).matches(Self.beat(.mergeable)))
    }

    @Test func anAnswerGitHubIsStillComputingChangesNothing() {
        #expect(Self.beat(.conflicting).matches(Self.beat(.unknown)))
        #expect(Self.beat(.conflicting).matches(Self.beat(nil)))
    }

    @Test func aRowWithoutTheFieldStillMatchesItsPullRequest() {
        #expect(Self.beat(nil).matches(Self.beat(nil)))
        #expect(Self.beat(.mergeable).matches(Self.beat(.mergeable)))
    }
}
