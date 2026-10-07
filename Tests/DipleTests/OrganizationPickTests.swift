import Foundation
import Testing
@testable import Diple

@Suite struct OrganizationPickTests {
    static let at = Date(timeIntervalSince1970: 1_790_000_000)

    static func pr(_ repo: String, _ number: Int, org: Bool?) -> PR {
        var p = PR(id: "\(repo)#\(number)", repo: repo, number: number, title: "t",
                   url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
                   updatedAt: at, createdAt: at, draft: false, author: "a", authorAvatar: nil,
                   isMine: false, headRef: "h", baseRef: "main", checks: .passing, approved: false,
                   threads: [], lastComment: nil)
        p.ownerIsOrganization = org
        return p
    }

    @Test func personalReposNeverBecomeTheTeamEvenWhenTheyOutnumberTheOrg() {
        let prs = [
            Self.pr("SalvyLTD/salvy-api", 8076, org: true),
            Self.pr("alifoo/hacking-club-pucpr", 4, org: false),
            Self.pr("alifoo/hacking-club-pucpr", 5, org: false),
            Self.pr("alifoo/hacking-club-pucpr", 6, org: false),
        ]
        #expect(AppModel.organization(of: prs) == "SalvyLTD")
    }

    @Test func withOnlyPersonalReposThereIsNoTeam() {
        #expect(AppModel.organization(of: [Self.pr("alifoo/x", 1, org: false)]) == "")
    }

    @Test func theOrgWithTheMostPullRequestsWins() {
        let prs = [Self.pr("acme/a", 1, org: true), Self.pr("beta/b", 2, org: true), Self.pr("beta/c", 3, org: true)]
        #expect(AppModel.organization(of: prs) == "beta")
    }

    @Test func aTieIsBrokenTheSameWayEveryTime() {
        let prs = [Self.pr("beta/b", 1, org: true), Self.pr("acme/a", 2, org: true)]
        #expect(AppModel.organization(of: prs) == "acme")
        #expect(AppModel.organization(of: prs.reversed()) == "acme")
    }

    @Test func pullRequestsCachedBeforeTheFieldStillPickAnOwner() {
        let prs = [Self.pr("acme/a", 1, org: nil), Self.pr("acme/b", 2, org: nil)]
        #expect(AppModel.organization(of: prs) == "acme")
    }
}
