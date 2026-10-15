import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct FindingPlaceTests {
    let changed = ["src/files.c", "src/server.c", "test/server_test.c", "Makefile"]

    @Test func aPathInThePullRequestKeepsItsLine() {
        #expect(FindingPlace.choose(path: "src/files.c", line: 40, inline: nil, changed: changed)
                == .line(path: "src/files.c", line: 40))
    }

    @Test func aBareFileNameFindsTheOneFileItNames() {
        #expect(FindingPlace.choose(path: "files.c", line: 40, inline: nil, changed: changed)
                == .line(path: "src/files.c", line: 40))
        #expect(FindingPlace.choose(path: "./Makefile", line: 3, inline: true, changed: changed)
                == .line(path: "Makefile", line: 3))
    }

    @Test func aNameTwoFilesShareGoesToTheConversation() {
        let both = ["src/files.c", "test/files.c"]
        #expect(FindingPlace.choose(path: "files.c", line: 744, inline: nil, changed: both) == .conversation)
    }

    @Test func aFileOutsideThePullRequestGoesToTheConversation() {
        #expect(FindingPlace.choose(path: "src/other.c", line: 1, inline: nil, changed: changed) == .conversation)
    }

    @Test func aFindingMarkedForTheConversationGoesThere() {
        #expect(FindingPlace.choose(path: "src/files.c", line: 40, inline: false, changed: changed) == .conversation)
    }

    @Test func aFindingWithoutALineGoesOnTheFile() {
        #expect(FindingPlace.choose(path: "src/server.c", line: nil, inline: nil, changed: changed)
                == .file(path: "src/server.c"))
    }

    @Test func withoutTheFileListThePathIsTrusted() {
        #expect(FindingPlace.choose(path: "files.c", line: 9, inline: nil, changed: [])
                == .line(path: "files.c", line: 9))
    }

    @Test func gitHubsLineErrorsCountAsOffTheDiff() {
        #expect(GitHubClient.isOffDiff(ClientError.graphql(["Line could not be resolved"])))
        #expect(GitHubClient.isOffDiff(ClientError.graphql(["pull_request_review_thread.line must be part of the diff"])))
        #expect(!GitHubClient.isOffDiff(ClientError.graphql(["Resource not accessible by integration"])))
        #expect(!GitHubClient.isOffDiff(ClientError.http(502)))
    }

    final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [String] = []
        func add(_ q: String) { lock.lock(); list.append(q); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return list }
    }

    static func model(rejectingLines: Bool, sent: Sent) -> AppModel {
        let world = FakeGitHub(.realistic())
        let transport = StubTransport { q in
            guard q.contains("mutation") else { return world.reply(q) }
            sent.add(q)
            if rejectingLines, q.contains("addPullRequestReviewThread"), q.contains("subjectType: LINE") {
                return .init(body: Data(#"{"data":null,"errors":[{"message":"Line could not be resolved"}]}"#.utf8))
            }
            return .init(body: Data("{\"data\":{}}".utf8))
        }
        let model = AppModel(
            client: GitHubClient(transport: transport, tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics())
        )
        model.preloadsTabs = false
        return model
    }

    static func finding(line: Int, inline: Bool? = nil) -> Finding {
        let flag = inline.map { #", "inline": \#($0)"# } ?? ""
        return try! JSONDecoder().decode(Finding.self, from: Data("""
        {"path": "src/a.ts", "line": \(line), "category": "correctness", "verdict": "confirmed",
         "summary": "a bug", "detail": "details"\(flag)}
        """.utf8))
    }

    @Test func aLineOffTheDiffIsPostedOnTheFileInstead() async {
        let sent = Sent()
        let model = Self.model(rejectingLines: true, sent: sent)
        await model.refresh()
        let finding = Self.finding(line: 744)
        await model.postOnGitHub(finding, on: model.queue.toReview[0])
        #expect(model.posted.contains(finding.id))
        #expect(sent.all.contains { $0.contains("subjectType: FILE") && $0.contains("Line 744:") })
    }

    @Test func aConversationFindingIsAPullRequestComment() async {
        let sent = Sent()
        let model = Self.model(rejectingLines: false, sent: sent)
        await model.refresh()
        let finding = Self.finding(line: 3, inline: false)
        await model.postOnGitHub(finding, on: model.queue.toReview[0])
        #expect(model.posted.contains(finding.id))
        #expect(sent.all.contains { $0.contains("addComment") })
        #expect(!sent.all.contains { $0.contains("addPullRequestReviewThread") })
    }
}
