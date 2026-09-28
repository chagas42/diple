import Foundation
import Testing
@testable import Diple

@Suite struct UncertainMutationTests {
    static let now = ISO8601DateFormatter().string(from: Date())
    static let old = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))

    static func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }

    static func check(_ node: [String: Any]) -> StubTransport.Reply {
        .init(body: json(["data": ["viewer": ["login": "you"], "node": node]]))
    }

    static func stub(
        mutation: @escaping @Sendable (String) -> StubTransport.Reply,
        check: @escaping @Sendable (String) -> StubTransport.Reply
    ) -> StubTransport {
        StubTransport { q in q.contains("MutationCheck") ? check(q) : mutation(q) }
    }

    static func client(_ stub: StubTransport, telemetry: Telemetry = .shared) -> GitHubClient {
        GitHubClient(transport: stub, tokens: CountingTokens(), metrics: Metrics(), telemetry: telemetry, retryDelays: [.zero, .zero])
    }

    static func lastComment(by author: String, at: String) -> [String: Any] {
        ["comments": ["nodes": [["author": ["login": author], "createdAt": at]]]]
    }

    @Test func aReplyThatLandedDespiteA502IsASuccess() async throws {
        let stub = Self.stub(mutation: { _ in .init(status: 502) }, check: { _ in Self.check(Self.lastComment(by: "you", at: Self.now)) })
        try await Self.client(stub).reply(threadId: "T1", body: "done")
        #expect(stub.queries.filter { !$0.contains("MutationCheck") }.count == 1)
    }

    @Test func aReplyThatDidNotLandStillFails() async {
        for (author, at) in [("someone", Self.now), ("you", Self.old)] {
            let stub = Self.stub(mutation: { _ in .init(status: 504) }, check: { _ in Self.check(Self.lastComment(by: author, at: at)) })
            await #expect(throws: ClientError.self) { try await Self.client(stub).reply(threadId: "T1", body: "done") }
        }
    }

    @Test func aTimeoutIsAsUncertainAsA502() async throws {
        let stub = Self.stub(mutation: { _ in .init(failure: .timedOut) }, check: { _ in Self.check(Self.lastComment(by: "you", at: Self.now)) })
        try await Self.client(stub).reply(threadId: "T1", body: "done")
    }

    @Test func aResolveThatLandedIsASuccess() async throws {
        let stub = Self.stub(mutation: { _ in .init(status: 503) }, check: { _ in Self.check(["isResolved": true]) })
        try await Self.client(stub).resolve(threadId: "T1")
        let open = Self.stub(mutation: { _ in .init(status: 503) }, check: { _ in Self.check(["isResolved": false]) })
        await #expect(throws: ClientError.self) { try await Self.client(open).resolve(threadId: "T1") }
    }

    @Test func aFindingWhoseThreadLandedGoesOnToSubmitTheReview() async throws {
        let stub = Self.stub(
            mutation: { q in q.contains("addPullRequestReviewThread") ? .init(status: 502) : .init(body: Self.json(["data": [:]])) },
            check: { _ in Self.check(["reviews": ["nodes": [[
                "author": ["login": "you"],
                "comments": ["nodes": [["path": "src/a.swift", "createdAt": Self.now]]],
            ]]]]) }
        )
        try await Self.client(stub).startThread(prId: "PR1", path: "src/a.swift", line: 3, body: "look")
        #expect(stub.queries.contains { $0.contains("submitPullRequestReview") })
    }

    @Test func aFindingWhoseReviewWasSubmittedDespiteA504IsASuccess() async throws {
        let stub = Self.stub(
            mutation: { q in q.contains("submitPullRequestReview") ? .init(status: 504) : .init(body: Self.json(["data": [:]])) },
            check: { _ in Self.check(["reviews": ["nodes": [["author": ["login": "you"], "submittedAt": Self.now]]]]) }
        )
        try await Self.client(stub).startThread(prId: "PR1", path: "src/a.swift", line: 3, body: "look")
    }

    @Test func anErrorThatIsNotUncertainIsNotChecked() async {
        let stub = Self.stub(mutation: { _ in .init(status: 500) }, check: { _ in Self.check(["isResolved": true]) })
        await #expect(throws: ClientError.self) { try await Self.client(stub).resolve(threadId: "T1") }
        #expect(!stub.queries.contains { $0.contains("MutationCheck") })
    }

    @Test func theCheckIsCountedAsLandedOrLost() async throws {
        let posthog = StubTransport { _ in .init(status: 200) }
        let telemetry = TelemetryTests.make(posthog)
        let landed = Self.stub(mutation: { _ in .init(status: 502) }, check: { _ in Self.check(["isResolved": true]) })
        try await Self.client(landed, telemetry: telemetry).resolve(threadId: "T1")
        let lost = Self.stub(mutation: { _ in .init(status: 502) }, check: { _ in Self.check(["isResolved": false]) })
        _ = try? await Self.client(lost, telemetry: telemetry).resolve(threadId: "T1")

        await telemetry.flush()
        let props = TelemetryTests.events(in: try #require(posthog.bodies.first))
            .filter { $0["event"] as? String == "github_retry" }
            .map { $0["properties"] as! [String: Any] }
        #expect(props.map { $0["outcome"] as? String } == ["landed", "lost"])
        #expect(props.allSatisfy { $0["request"] as? String == "mutation" && $0["status"] as? Int == 502 })
    }
}
