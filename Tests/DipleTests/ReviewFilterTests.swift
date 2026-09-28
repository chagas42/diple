import Foundation
import Testing
@testable import Diple

@Suite struct ReviewFilterTests {
    static func pr(_ n: Int, by author: String, askedYou: Bool = false) -> PR {
        PR(id: "\(n)", repo: "o/r", number: n, title: "t\(n)",
           url: URL(string: "https://github.com/o/r/pull/\(n)")!,
           updatedAt: Date(), createdAt: Date(), draft: false,
           author: author, authorAvatar: nil, isMine: false,
           headRef: "h", baseRef: "main", checks: .none, approved: false,
           threads: [], lastComment: nil, askedYou: askedYou)
    }

    static let fromTeam = pr(1, by: "bea")
    static let fromOutside = pr(2, by: "stranger")
    static let byName = pr(3, by: "stranger", askedYou: true)
    static let requests = [fromOutside, fromTeam, byName]

    @Test func everyoneKeepsGitHubsOrderAndQuietsNoOne() {
        #expect(ReviewFilter.everyone.order(Self.requests, picked: ["bea"]).map(\.number) == [2, 1, 3])
        #expect(!ReviewFilter.everyone.quiets(Self.fromOutside, picked: ["bea"]))
    }

    @Test func pickedFirstPutsTeammatesAndByNameAheadButQuietsNoOne() {
        #expect(ReviewFilter.pickedFirst.order(Self.requests, picked: ["bea"]).map(\.number) == [1, 3, 2])
        #expect(!ReviewFilter.pickedFirst.quiets(Self.fromOutside, picked: ["bea"]))
    }

    @Test func onlyPickedQuietsOutsidersButNotWhoAskedYouByName() {
        #expect(ReviewFilter.onlyPicked.quiets(Self.fromOutside, picked: ["bea"]))
        #expect(!ReviewFilter.onlyPicked.quiets(Self.fromTeam, picked: ["bea"]))
        #expect(!ReviewFilter.onlyPicked.quiets(Self.byName, picked: ["bea"]))
    }

    @Test func withNobodyPickedEveryFilterActsLikeEveryone() {
        for f in ReviewFilter.allCases {
            #expect(f.order(Self.requests, picked: []).map(\.number) == [2, 1, 3])
            #expect(!f.quiets(Self.fromOutside, picked: []))
        }
    }

    @Test func aQuietRequestSpeaksUpWhenSomeoneWritesOnIt() {
        #expect(ReviewFilter.staysQuiet(unread: true, reason: .reviewRequested))
        #expect(ReviewFilter.staysQuiet(unread: false, reason: nil))
        #expect(!ReviewFilter.staysQuiet(unread: true, reason: .repliedToYou))
        #expect(!ReviewFilter.staysQuiet(unread: true, reason: .commented))
    }

    @Test func aRequestToYouByNameIsReadFromGitHub() throws {
        let json = """
        {"id":"P","number":9,"title":"t","url":"https://github.com/o/r/pull/9",
         "updatedAt":"2026-09-28T10:00:00Z","isDraft":false,"headRefName":"h","baseRefName":"main",
         "repository":{"nameWithOwner":"o/r"},"author":{"login":"stranger","__typename":"User"},
         "reviewDecision":null,
         "reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"Team"}},
                                    {"requestedReviewer":{"__typename":"User","login":"me"}}]},
         "comments":{"nodes":[]},"reviewThreads":{"nodes":[]},"commits":{"nodes":[]}}
        """
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let raw = try d.decode(RawPR.self, from: Data(json.utf8))
        #expect(PR(raw, meuLogin: "me")?.asksYouByName == true)
        #expect(PR(raw, meuLogin: "someone-else")?.asksYouByName == false)
    }
}
