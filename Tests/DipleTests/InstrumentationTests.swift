import Foundation
import Testing
@testable import Diple

@MainActor
@Suite struct InstrumentationTests {
    @MainActor
    final class Rig {
        let github = FakeGitHub(.realistic())
        let sink = StubTransport { _ in .init(status: 200) }
        let telemetry: Telemetry
        let model: AppModel
        var opened: [URL] = []

        init() {
            var c = Telemetry.Config()
            c.key = "phc_test"
            c.batchSize = 10_000
            telemetry = Telemetry(config: c, transport: sink)
            let world = github
            let transport = StubTransport { q in
                q.contains("mutation") ? .init(body: Data("{\"data\":{}}".utf8)) : world.reply(q)
            }
            model = AppModel(
                client: GitHubClient(transport: transport, tokens: CountingTokens(), metrics: Metrics()),
                store: Store(directory: StoreDiffTests.tempDirectory(), metrics: Metrics()),
                telemetry: telemetry
            )
            model.preloadsTabs = false
            model.startTelemetry()
        }

        func sent() async -> [(name: String, properties: [String: Any])] {
            await telemetry.flush()
            return sink.bodies.flatMap(TelemetryTests.events).map {
                ($0["event"] as! String, $0["properties"] as! [String: Any])
            }
        }
    }

    static func finding() -> Finding {
        try! JSONDecoder().decode(Finding.self, from: Data("""
        {"path": "src/a.ts", "line": 3, "category": "correctness", "verdict": "confirmed",
         "summary": "a bug", "detail": "details"}
        """.utf8))
    }

    @Test func theFirstRefreshOfTheDayCountsAnActiveUserOnce() async {
        let rig = Rig()
        await rig.model.refresh()
        await rig.model.refresh()
        let active = await rig.sent().filter { $0.name == "app_active" }
        #expect(active.count == 1)
        #expect(active.first?.properties["to_review"] as? Int == 4)
        #expect(active.first?.properties["mine"] as? Int == 14)
    }

    @Test func openingAPullRequestSaysWhereFrom() async {
        let rig = Rig()
        await rig.model.refresh()
        rig.model.openURL = { _ in }
        let pr = rig.model.queue.mine[0]
        rig.model.open(pr, from: .notch)
        rig.model.open(pr, from: .menuBar)
        let sources = await rig.sent().filter { $0.name == "pr_opened" }.map { $0.properties["source"] as? String }
        #expect(sources == ["notch", "menu_bar"])
    }

    @Test func replyingAndResolvingAreCounted() async {
        let rig = Rig()
        _ = await rig.model.reply(thread: "T_1_0", text: "on it")
        _ = await rig.model.resolve(thread: "T_1_0")
        _ = await rig.model.reply(thread: "T_1_0", text: "   ")
        let names = await rig.sent().map(\.name)
        #expect(names.filter { $0 == "reply_sent" }.count == 1)
        #expect(names.filter { $0 == "thread_resolved" }.count == 1)
    }

    @Test func postingAFindingIsCounted() async {
        let rig = Rig()
        await rig.model.refresh()
        await rig.model.postOnGitHub(Self.finding(), on: rig.model.queue.toReview[0])
        let names = await rig.sent().map(\.name)
        #expect(names.contains("finding_posted"))
    }

    @Test func aReviewThatCannotStartStillReportsHowItEnded() async {
        let rig = Rig()
        await rig.model.refresh()
        await rig.model.runAIReview(rig.model.queue.mine[0])
        let events = await rig.sent()
        #expect(events.filter { $0.name == "ai_review_started" }.count == 1)
        let finished = events.first { $0.name == "ai_review_finished" }
        #expect(finished?.properties["outcome"] as? String == "failed")
        #expect(finished?.properties["findings"] as? Int == 0)
        #expect(finished?.properties["duration"] as? String == "lt_30s")
    }

    @Test func someoneElsesPullRequestCannotBeReviewedWithAI() async {
        let rig = Rig()
        await rig.model.refresh()
        let theirs = rig.model.queue.toReview[0]
        #expect(!theirs.isMine)
        await rig.model.runAIReview(theirs)
        #expect(rig.model.run(theirs.key) == nil)
        let names = await rig.sent().map(\.name)
        #expect(!names.contains("ai_review_started"))
        #expect(!names.contains("ai_review_finished"))
    }

    @Test func aMapThatCannotBeBuiltStillReportsIt() async {
        let rig = Rig()
        await rig.model.refresh()
        await rig.model.buildMap(rig.model.queue.toReview[0])
        let map = await rig.sent().first { $0.name == "map_built" }
        #expect(map?.properties["outcome"] as? String == "failed")
        #expect(map?.properties["prs_in_stack"] as? Int == 1)
    }

    @Test func nothingIdentifyingEverLeaves() async {
        let rig = Rig()
        await rig.model.refresh()
        rig.model.openURL = { _ in }
        rig.model.open(rig.model.queue.mine[0], from: .window)
        await rig.model.runAIReview(rig.model.queue.toReview[0])
        await rig.model.buildMap(rig.model.queue.toReview[0])
        _ = await rig.model.reply(thread: "T_1_0", text: "secret words")
        await rig.telemetry.flush()
        let payload = rig.sink.bodies.map { String(decoding: $0, as: UTF8.self) }.joined()
        #expect(!payload.isEmpty)
        for leak in ["acme/", "repo0", "Change ", "teammate", "\"you\"", "secret words", "src/", "T_1_0"] {
            #expect(!payload.contains(leak), "payload contains \(leak)")
        }
    }

    @Test func optedOutUsersSendNothingFromAnyPath() async {
        let rig = Rig()
        rig.model.settings.shareUsage = false
        await rig.model.refresh()
        rig.model.openURL = { _ in }
        rig.model.open(rig.model.queue.mine[0], from: .notch)
        _ = await rig.model.reply(thread: "T_1_0", text: "ok")
        await rig.model.runAIReview(rig.model.queue.toReview[0])
        let events = await rig.sent()
        #expect(events.isEmpty)
    }
}
