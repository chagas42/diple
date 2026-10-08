import Foundation
import Testing
@testable import Diple

@Suite struct ReviewRotationTests {
    static func client(_ json: String) -> (GitHubClient, StubTransport) {
        let transport = StubTransport(body: Data(json.utf8))
        return (GitHubClient(transport: transport, tokens: CountingTokens(), metrics: Metrics()), transport)
    }

    @Test func readsTheTeamSettingsGitHubReturns() {
        let r = ReviewRotation(team: [
            "reviewRequestDelegationEnabled": true,
            "reviewRequestDelegationAlgorithm": "LOAD_BALANCE",
            "reviewRequestDelegationMemberCount": 2,
            "reviewRequestDelegationNotifyTeam": true,
        ])
        #expect(r == ReviewRotation(enabled: true, algorithm: .loadBalance, reviewers: 2, notifyTeam: true))
        #expect(ReviewRotation(team: [:]) == nil)
    }

    @Test func theMutationCarriesEveryChoice() {
        let m = ReviewRotation.mutation(teamId: "T_1", ReviewRotation(enabled: true, algorithm: .roundRobin, reviewers: 3, notifyTeam: false))
        #expect(GitHubClient.isMutation(m))
        #expect(m.contains("enabled: true"))
        #expect(m.contains("algorithm: ROUND_ROBIN"))
        #expect(m.contains("teamMemberCount: 3"))
        #expect(m.contains("notifyTeam: false"))
        #expect(!m.contains("T_1"))
    }

    @Test func aMissingScopeAsksForTheRefreshCommand() {
        #expect(ReviewRotation.needsScope(ClientError.graphql(["Your token has not been granted the required scopes to execute this query."])))
        #expect(!ReviewRotation.needsScope(ClientError.graphql(["Resource not accessible by integration"])))
        #expect(!ReviewRotation.needsScope(ClientError.http(500)))
    }

    @Test func teamsSayWhetherYouCanChangeThem() async throws {
        let (client, transport) = Self.client("""
        {"data":{"organization":{"teams":{"nodes":[
          {"id":"T_eng","slug":"engineering","name":"Engineering","viewerCanAdminister":true,"members":{"totalCount":10}},
          {"id":"T_data","slug":"data","name":"Data","viewerCanAdminister":false,"members":{"totalCount":3}}
        ]}}}}
        """)
        let teams = try await client.fetchMyTeams(org: "SalvyLTD", viewer: "chagas42")
        #expect(teams.map(\.canAdminister) == [true, false])
        #expect(teams.map(\.nodeId) == ["T_eng", "T_data"])
        #expect(transport.queries.first?.contains("viewerCanAdminister") == true)
    }

    @Test func savingSendsTheTeamIdAsAVariableAndReadsBackTheResult() async throws {
        let (client, transport) = Self.client("""
        {"data":{"updateTeamReviewAssignment":{"team":{
          "reviewRequestDelegationEnabled":true,"reviewRequestDelegationAlgorithm":"ROUND_ROBIN",
          "reviewRequestDelegationMemberCount":1,"reviewRequestDelegationNotifyTeam":false}}}}
        """)
        let wanted = ReviewRotation(enabled: true, algorithm: .roundRobin, reviewers: 1, notifyTeam: false)
        #expect(try await client.updateRotation(teamId: "T_eng", wanted) == wanted)
        let body = try #require(transport.bodies.first)
        let vars = (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["variables"] as? [String: String]
        #expect(vars == ["id": "T_eng"])
    }

    @Test func theForcedRoleOverridesWhatGitHubSaid() {
        let teams = [GitHubClient.TeamRef(slug: "a", name: "A", members: 1, canAdminister: true)]
        #expect(AppModel.teams(teams, as: "member").first?.canAdminister == false)
        #expect(AppModel.teams(teams, as: "admin").first?.canAdminister == true)
        #expect(AppModel.teams(teams, as: nil) == teams)
        #expect(AppModel.teams(teams, as: "owner") == teams)
    }

    @Test func loadBalanceAsksWhoeverHasTheFewestReviewsAndNeverTheAuthor() {
        var simulation = RotationSimulation(people: 4)
        simulation.loads = [0, 3, 0, 1]
        let rotation = ReviewRotation(enabled: true, algorithm: .loadBalance, reviewers: 2)
        #expect(simulation.pick(rotation, author: 0) == [2, 3])
        #expect(simulation.loads == [0, 3, 1, 2])
    }

    @Test func roundRobinTakesTurnsSkippingTheAuthor() {
        var simulation = RotationSimulation(people: 4)
        let rotation = ReviewRotation(enabled: true, algorithm: .roundRobin, reviewers: 2)
        #expect(simulation.pick(rotation, author: 1) == [0, 2])
        #expect(simulation.pick(rotation, author: 0) == [3, 1])
        #expect(simulation.pick(rotation, author: 3) == [2, 0])
    }

    @Test func withTheRotationOffEveryoneButTheAuthorIsAsked() {
        var simulation = RotationSimulation(people: 3)
        #expect(simulation.pick(ReviewRotation(enabled: false), author: 2) == [0, 1])
    }

    @Test func aTeamSmallerThanTheAskStillPicksWhoItCan() {
        var simulation = RotationSimulation(people: 2)
        #expect(simulation.pick(ReviewRotation(enabled: true, reviewers: 5), author: 0) == [1])
    }

    @Test func theOrgOwnerOutranksTheTeamMaintainer() {
        let admin = GitHubClient.TeamRef(slug: "e", name: "E", members: 1, canAdminister: true)
        let member = GitHubClient.TeamRef(slug: "e", name: "E", members: 1)
        #expect(TeamAccess(team: admin, orgAdmin: true) == .orgOwner)
        #expect(TeamAccess(team: admin, orgAdmin: false) == .maintainer)
        #expect(TeamAccess(team: member, orgAdmin: false) == .member)
    }

    @Test func theRotationReadKnowsWhetherYouOwnTheOrg() async throws {
        let (client, _) = Self.client("""
        {"data":{"organization":{"viewerCanAdminister":true,"team":{
          "reviewRequestDelegationEnabled":false,"reviewRequestDelegationAlgorithm":"ROUND_ROBIN",
          "reviewRequestDelegationMemberCount":1,"reviewRequestDelegationNotifyTeam":true}}}}
        """)
        let read = try #require(try await client.fetchRotation(org: "SalvyLTD", slug: "engineering"))
        #expect(read.orgAdmin)
        #expect(read.rotation == ReviewRotation(enabled: false, algorithm: .roundRobin, reviewers: 1, notifyTeam: true))
    }

    @Test func theReviewFilterSaysWhenARotationAlreadyPicksForYou() {
        #expect(ReviewRotation.filterNote([]) == nil)
        #expect(ReviewRotation.filterNote(["Engineering"])?.hasPrefix("Engineering uses review rotation") == true)
        #expect(ReviewRotation.filterNote(["Data", "Design", "Engineering"])?.hasPrefix("Data, Design and Engineering use") == true)
    }

    @Test func codeOwnersFindTheReposWhereTheTeamIsTheReviewer() {
        let files = [
            "salvy-api": "*       @SalvyLTD/engineering\n",
            "chatwoot": "*.js @pranavrajs\n# @SalvyLTD/engineering is only a comment here\n",
            "infra": "/terraform/ @someone @salvyltd/Engineering\n",
            "site": "* @SalvyLTD/designers\n",
        ]
        #expect(TeamFit.repos(owning: "engineering", org: "SalvyLTD", in: files) == ["infra", "salvy-api"])
        #expect(TeamFit.repos(owning: "data", org: "SalvyLTD", in: files).isEmpty)
    }

    @Test func aTeamNobodyAsksGetsNothingFromARotation() {
        #expect(TeamFit(requests: 541, repos: ["salvy-api"]).verdict == .works)
        #expect(TeamFit(requests: 0, repos: ["site"]).verdict == .ownsButQuiet)
        #expect(TeamFit(requests: 0, repos: []).verdict == .neverAsked)
        #expect(TeamFit(requests: 3, repos: []).verdict == .works)
    }

    @Test func requestsAreCountedForTheTeamOverTheLastMonth() async throws {
        let (client, transport) = Self.client(#"{"data":{"search":{"issueCount":541}}}"#)
        let since = ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z")!
        #expect(try await client.teamRequests(org: "SalvyLTD", slug: "engineering", since: since) == 541)
        #expect(transport.queries.first?.contains("team-review-requested:SalvyLTD/engineering created:>=2026-09-07") == true)
    }

    @Test func onlyPeopleWhoCanChangeTheRotationSeeItsStep() {
        #expect(Onboarding.steps(managesRotation: true).contains(.reviews))
        #expect(!Onboarding.steps(managesRotation: false).contains(.reviews))
        #expect(Onboarding.steps(managesRotation: false).count == Onboarding.Step.allCases.count - 1)
        #expect(Onboarding.steps(managesRotation: false, start: .reviews).contains(.reviews))
    }

    @Test func pilesStayBoundedEvenWhenEveryoneIsPinged() {
        var simulation = RotationSimulation(people: 4)
        let start = simulation.loads.reduce(0, +)
        for n in 0..<50 {
            let chosen = simulation.pick(ReviewRotation(enabled: false), author: n % 4)
            simulation.settle(chosen.count)
        }
        #expect(simulation.loads.reduce(0, +) <= start + 3)
        #expect(simulation.loads.allSatisfy { $0 <= 6 })
    }
}
