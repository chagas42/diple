import Foundation
import Testing
@testable import Diple

@Suite struct RankingPageTests {
    let monday = ISO8601DateFormatter().date(from: "2026-10-05T03:00:00Z")!

    static func node(_ submittedAt: String?) -> [String: Any] {
        ["reviews": ["nodes": submittedAt.map { [["submittedAt": $0]] } ?? []]]
    }

    static func search(_ nodes: [[String: Any]], next: String? = nil) -> [String: Any] {
        ["issueCount": nodes.count,
         "pageInfo": ["hasNextPage": next != nil, "endCursor": next as Any],
         "nodes": nodes]
    }

    @Test func aReviewThisWeekOnAnOlderPullRequestCounts() {
        let page = RankingPage(Self.search([
            Self.node("2026-10-05T14:10:00Z"),
            Self.node("2026-10-02T18:00:00Z"),
            Self.node(nil),
        ]), from: monday)
        #expect(page?.reviewed == 1)
        #expect(page?.next == nil)
    }

    @Test func aMissingSearchIsNoRow() {
        #expect(RankingPage(nil, from: monday) == nil)
        #expect(RankingPage(["nodes": []], from: monday) == nil)
    }

    @Test func aFullPageSaysWhereToGoOn() {
        let page = RankingPage(Self.search([Self.node("2026-10-05T10:00:00Z")], next: "abc"), from: monday)
        #expect(page?.next == "abc")
    }

    @Test func theQueryAsksForActivityFromTheExactStart() {
        let q = RankingPage.query(org: "acme", login: "bea", from: monday)
        #expect(q == "is:pr org:acme reviewed-by:bea updated:>=2026-10-05T03:00:00Z")
    }

    @Test func aPersonWithMoreThanOnePageIsCountedInFull() async throws {
        let first = Self.search([Self.node("2026-10-05T10:00:00Z"), Self.node("2026-10-05T11:00:00Z")], next: "p2")
        let second = Self.search([Self.node("2026-10-05T12:00:00Z"), Self.node("2026-09-30T12:00:00Z")])
        let firstBody = try JSONSerialization.data(withJSONObject: ["data": ["u0": first]])
        let secondBody = try JSONSerialization.data(withJSONObject: ["data": ["u": second]])
        let transport = StubTransport { q in
            .init(body: q.contains("p2") ? secondBody : firstBody)
        }
        let client = GitHubClient(transport: transport, tokens: CountingTokens(), metrics: Metrics())
        let rows = try await client.fetchRanking(org: "acme", people: [Person.placeholder("bea")], from: monday)
        #expect(rows.map(\.reviews) == [3])
        #expect(transport.queries.count == 2)
    }
}
