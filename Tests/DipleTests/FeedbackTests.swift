import Foundation
import Testing
@testable import Diple

@Suite struct FeedbackTextTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let input: String
        let mustContain: [String]
        let mustNotContain: [String]
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "GitHub classic token",
             input: "my token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 leaked",
             mustContain: ["[redacted token]"], mustNotContain: ["ghp_ABCDEF"]),
        Case(name: "fine-grained token",
             input: "github_pat_11AAAAAAA0123456789_abcdefghijklmnopqrstuvwxyz",
             mustContain: ["[redacted token]"], mustNotContain: ["github_pat_11"]),
        Case(name: "API key",
             input: "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123",
             mustContain: ["[redacted key]"], mustNotContain: ["sk-ant-api03"]),
        Case(name: "AWS key",
             input: "AKIAIOSFODNN7EXAMPLE is mine",
             mustContain: ["[redacted key]"], mustNotContain: ["AKIAIOSFODNN7EXAMPLE"]),
        Case(name: "bearer header",
             input: "Authorization: Bearer abcdefghijklmnop.qrstuvwx",
             mustContain: ["Bearer [redacted]"], mustNotContain: ["abcdefghijklmnop"]),
        Case(name: "e-mail",
             input: "write me at marina.souza@example.com please",
             mustContain: ["[email]"], mustNotContain: ["marina.souza@"]),
        Case(name: "home path",
             input: "crashed in /Users/chagas42/@work/api/src/a.ts",
             mustContain: ["~/@work/api/src/a.ts"], mustNotContain: ["chagas42"]),
        Case(name: "bidi override and control characters",
             input: "safe\u{202E}evil\u{0007}text",
             mustContain: ["safeeviltext"], mustNotContain: ["\u{202E}", "\u{0007}"]),
        Case(name: "ordinary text survives",
             input: "  The map is great, but the legend overlaps.  ",
             mustContain: ["The map is great, but the legend overlaps."], mustNotContain: ["  The"]),
    ]

    @Test(arguments: cases)
    func sanitizes(_ c: Case) {
        let out = FeedbackText.clean(c.input)
        for s in c.mustContain { #expect(out.contains(s), "missing \(s) in \(out)") }
        for s in c.mustNotContain { #expect(!out.contains(s), "kept \(s) in \(out)") }
    }

    @Test func longTextIsCutAndBlankRunsCollapse() {
        let out = FeedbackText.clean(String(repeating: "a", count: 5000))
        #expect(out.count == FeedbackText.limit)
        #expect(FeedbackText.clean("a\n\n\n\n\n\nb") == "a\n\n\nb")
        #expect(FeedbackText.clean("é") == "é".precomposedStringWithCanonicalMapping)
        #expect(FeedbackText.clean("日本語と emoji 🚀") == "日本語と emoji 🚀")
    }

    @Test func theIssueLinkIsPrefilledAndClean() throws {
        let url = FeedbackText.issueURL(
            title: "Map legend overlaps",
            description: "token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 in /Users/me/x",
            feature: .map,
            diagnostics: FeedbackText.diagnostics(feature: .map, version: "1.2.3", os: "26.5", machine: "Mac16,12")
        )
        let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(c.host == "github.com")
        #expect(c.path == "/chagas42/diple/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["title"] == "Map legend overlaps")
        #expect(items["labels"] == "from-app")
        let body = try #require(items["body"])
        #expect(body.contains("[redacted token]"))
        #expect(body.contains("~/x"))
        #expect(body.contains("| Diple | 1.2.3 |"))
        #expect(body.contains("PR map"))
        #expect(!body.contains("ghp_"))
    }

    @Test func aHugeReportStillFitsInALink() {
        let wide = String(repeating: "日本", count: 1500)
        let url = FeedbackText.issueURL(title: "", description: wide, feature: .aiReview, diagnostics: nil)
        #expect(url.absoluteString.count <= FeedbackText.maxURLLength)
        #expect(url.absoluteString.contains("cut%20to%20fit"))
    }

    @Test func anEmptyTitleNamesTheFeature() throws {
        let url = FeedbackText.issueURL(title: "  ", description: "x", feature: .queue, diagnostics: nil)
        let c = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(c.queryItems?.first { $0.name == "title" }?.value == "Queue: ")
    }

    @Test func theEventItselfCannotCarryRawText() {
        let e = TelemetryEvent.feedbackSubmitted(feature: .map, rating: .down, text: "mail me: a@b.co ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123")
        #expect(e.properties["text"] == .text("mail me: [email] [redacted token]"))
        #expect(e.properties["feature"] == .text("map"))
        #expect(e.properties["rating"] == .text("down"))
        #expect(Set(e.properties.keys) == ["feature", "rating", "text"])
    }
}

@MainActor
@Suite struct QuickFeedbackTests {
    static func model(consent: Bool = true) -> (AppModel, Telemetry, StubTransport) {
        let sink = StubTransport { _ in .init(status: 200) }
        var c = Telemetry.Config()
        c.key = "phc_test"
        let telemetry = Telemetry(config: c, transport: sink)
        let model = AppModel(
            client: GitHubClient(transport: StubTransport(body: Data()), tokens: CountingTokens(), metrics: Metrics()),
            store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics()),
            telemetry: telemetry
        )
        model.startTelemetry()
        model.settings.shareUsage = consent
        return (model, telemetry, sink)
    }

    @Test func quickFeedbackIsSentRightAwayAndSanitized() async throws {
        let (model, telemetry, sink) = Self.model()
        model.sendQuickFeedback(feature: .aiReview, rating: .up, text: "love it — ping me at x@y.io")
        let deadline = ContinuousClock.now + .seconds(5)
        while sink.bodies.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        await telemetry.flush()
        let events = sink.bodies.flatMap(TelemetryTests.events)
        let e = try #require(events.first { $0["event"] as? String == "feedback_submitted" })
        let props = e["properties"] as! [String: Any]
        #expect(props["feature"] as? String == "ai_review")
        #expect(props["rating"] as? String == "up")
        #expect(props["text"] as? String == "love it — ping me at [email]")
    }

    @Test func withSharingOffQuickFeedbackIsUnavailableAndSendsNothing() async {
        let (model, telemetry, sink) = Self.model(consent: false)
        #expect(!model.canSendQuickFeedback)
        model.sendQuickFeedback(feature: .map, rating: nil, text: "hello")
        await telemetry.flush()
        #expect(sink.bodies.isEmpty)
    }

    @Test func theIssuePathOpensGitHubAndSendsNothing() async {
        let (model, telemetry, sink) = Self.model()
        var opened: [URL] = []
        model.openURL = { opened.append($0) }
        model.openIssue(title: "Crash", description: "steps", feature: .pullRequest, diagnostics: true)
        await telemetry.flush()
        #expect(opened.count == 1)
        #expect(opened.first?.host == "github.com")
        #expect(opened.first?.absoluteString.contains("Mac") == true)
        #expect(sink.bodies.isEmpty)
    }

    @Test func everyNotchTabHasAFeature() {
        #expect(Set(AppModel.NotchTab.allCases.map(\.feedbackFeature)) == [.queue, .team, .ranking, .activity])
    }
}
